from flask import (
    Blueprint, render_template, request, redirect, url_for, flash, session, g,
    jsonify, current_app
)
from flask_login import login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from .db import get_db 
from .models import User 
import os
import json
from dotenv import load_dotenv  # Added import

# Load environment variables from .env file
load_dotenv()  # Added call

import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
try:
    from emotion_chatbot import (
        detect_emotion, load_models, load_knowledge_base,
        retrieve_context, build_prompt_user_part, generate_response 
    )
    try:
        print("Attempting to load models...")
        embedder, generator = load_models()
        knowledge_data = load_knowledge_base()
        corpus = [entry["text"] for entry in knowledge_data] if knowledge_data else []
        if corpus and embedder:
             print(f"Encoding {len(corpus)} corpus entries...")
             corpus_embeddings = embedder.encode(corpus, convert_to_tensor=True)
             print("Corpus encoded.")
        else:
             corpus_embeddings = None
        MODELS_LOADED = True
        print("Models and knowledge base processed.")
    except Exception as e:
        print(f"ERROR: Failed to load AI models or knowledge base: {e}")
        embedder, generator, knowledge_data, corpus, corpus_embeddings = None, None, [], [], None
        MODELS_LOADED = False

except ImportError as e:
    print(f"ERROR: Could not import emotion_chatbot functions: {e}")
    MODELS_LOADED = False
    embedder, generator, knowledge_data, corpus, corpus_embeddings = None, None, [], [], None
    def build_prompt_user_part(*args): return "Error: Prompt function not loaded."
    def generate_response(*args): return "Error: Generator function not loaded."
    def detect_emotion(*args): return "neutral"
    def retrieve_context(*args): return []


# --- Chat History Database Functions ---

def save_chat_message(user_id, sender, message, emotion=None):
    """Saves a chat message to the database."""
    db = get_db()
    try:
        db.execute(
            "INSERT INTO chat_history (user_id, sender, message, emotion) VALUES (?, ?, ?, ?)",
            (user_id, sender, message, emotion)
        )
        db.commit()
    except Exception as e:
        print(f"Error saving chat message: {e}")
        db.rollback()  # Rollback in case of error

def get_chat_history(user_id, limit=50):
    """Retrieves chat history for a user from the database."""
    db = get_db()
    history_cursor = db.execute(
        "SELECT sender, message, emotion, timestamp FROM chat_history WHERE user_id = ? ORDER BY timestamp DESC LIMIT ?",
        (user_id, limit)
    )
    history = history_cursor.fetchall()
    # Convert Row objects to dictionaries and reverse order to show oldest first
    return [dict(row) for row in reversed(history)]

# --- End Chat History Database Functions ---


# Define distress keywords (customize as needed)
DISTRESS_KEYWORDS = [
    "kill myself", "suicide", "end my life", "want to die",
    "hopeless", "can't go on", "no reason to live", "overwhelmed",
    "hurting myself", "self-harm"
]

# Suicide Hotline Information (expanded for global coverage)
SUICIDE_HOTLINE_MESSAGE = (
    "I understand you're going through immense pain right now. Please know that you're not alone and help is available.\n\n"
    "US/Canada: Call or text 988 (National Suicide Prevention Lifeline)\n"
    "UK: Call 111 or 116 123 (Samaritans)\n"
    "India: Emergency: 112\n"
    "      Suicide Hotline: 8888817666\n"
    "      Prana Lifeline: 1800 121 203040 (Call), +91-8489512307 (Chat)\n"
    "      Vandrevala Foundation: 9999-666-555 (Call), +1256662142 (Chat)\n"
    "\nThese services provide 24/7 free and confidential support for depression, anxiety, suicidal thoughts and other crises. "
    "Please reach out for help - you matter and people care about you."
)

# Function to check for distress keywords
def check_for_distress(message):
    message_lower = message.lower()
    for keyword in DISTRESS_KEYWORDS:
        if keyword in message_lower:
            return True
    return False

# Function to check for rain sound request
def check_for_rain_request(message):
    message_lower = message.lower()
    # Simple check, can be made more robust
    if "play rain" in message_lower or "rain sound" in message_lower:
        return True
    return False


main = Blueprint('main', __name__)


@main.route('/')
def index():
    """Serves the main landing page."""
    return render_template('landing.html')


@main.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.chat')) 
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        error = None

        if not username or not password:
             error = 'Username and password are required.'
        else:
            db = get_db()
            user_data = db.execute(
                'SELECT * FROM users WHERE username = ?', (username,)
            ).fetchone()

            if user_data is None:
                error = 'Incorrect username.'
            elif not check_password_hash(user_data['password'], password):
                error = 'Incorrect password.'

        if error is None:
            user_obj = User(user_data['id'], user_data['username'], user_data['password'])
            login_user(user_obj, remember=request.form.get('remember') == 'on') 
            flash('Login successful!', 'success')
            next_page = request.args.get('next') 
            return redirect(next_page or url_for('main.chat'))
        else:
            flash(error, 'danger') 

    return render_template('login.html', signup=False)

@main.route('/signup', methods=['GET', 'POST'])
def signup():
    if current_user.is_authenticated:
        return redirect(url_for('main.chat'))

    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        error = None
        db = get_db()

        if not username:
            error = 'Username is required.'
        elif not password:
            error = 'Password is required.'
        elif db.execute('SELECT id FROM users WHERE username = ?', (username,)).fetchone() is not None:
            error = f"Username '{username}' is already taken."

        if error is None:
            try:
                db.execute(
                    'INSERT INTO users (username, password) VALUES (?, ?)',
                    (username, generate_password_hash(password, method='pbkdf2:sha256', salt_length=16))
                )
                db.commit()
                flash('Account created successfully! Please log in.', 'success')
                return redirect(url_for('main.login'))
            except db.IntegrityError: 
                error = f"Username '{username}' is already taken."
            except Exception as e:
                error = f"An error occurred creating the account: {e}"
                db.rollback() 
        flash(error, 'danger')

    return render_template('login.html', signup=True)

@main.route('/logout')
@login_required 
def logout():
    logout_user()
    flash("You have been logged out.", "info")
    return redirect(url_for('main.index'))


@main.route('/faq')
def faq():
    """Serves the FAQ page."""
    return render_template('faq.html')

@main.route('/resources')
def resources():
    """Serves the Resources page."""
    return render_template('resources.html')

@main.route('/chat', methods=['GET', 'POST'])
@login_required
def chat():
    if not MODELS_LOADED or generator is None:
        if request.is_json:
            return jsonify({"error": "Chat functionality unavailable"}), 503
        else:
            flash("Chat functionality is currently unavailable.", "warning")
            return redirect(url_for('main.faq'))

    current_history = get_chat_history(current_user.id)
    if not current_history and request.method == 'GET': # Only add greeting on initial GET
        initial_greeting = f"Hello {current_user.username}, welcome! How are you feeling today?"
        save_chat_message(current_user.id, 'bot', initial_greeting, 'neutral')
        current_history = get_chat_history(current_user.id) # Reload history

    if request.method == 'POST':
        if not request.is_json:
            return jsonify({"error": "Invalid request format, JSON expected."}), 400

        data = request.get_json()
        user_message = data.get('message', '').strip()

        if not user_message:
            return jsonify({"error": "Empty message received."}), 400

        if user_message.lower() in ['exit', 'quit']:
            return jsonify({"bot_reply": "Chat session ended.", "emotion": "neutral", "action": "end_chat"})

        try:
            # --- Distress Check ---
            is_distress = check_for_distress(user_message)
            play_rain = check_for_rain_request(user_message)

            # Save user message to DB (using existing function)
            save_chat_message(current_user.id, 'user', user_message)

            # Process message and get bot reply
            emotion = detect_emotion(user_message)
            contexts = retrieve_context(user_message, emotion, corpus, corpus_embeddings, embedder, knowledge_data, k=1)
            prompt_user_part = build_prompt_user_part(user_message, emotion, contexts)
            bot_reply = generate_response(prompt_user_part, generator, current_user.username)
            bot_emotion = emotion # Use detected emotion for bot response context, or refine later

            # --- Append Hotline Message if Distress Detected ---
            if is_distress:
                bot_reply += f"\n\n{SUICIDE_HOTLINE_MESSAGE}"
                bot_emotion = "concerned" # Override emotion

            # Save bot reply to DB
            save_chat_message(current_user.id, 'bot', bot_reply, bot_emotion)

            response_data = {
                "bot_reply": bot_reply,
                "emotion": bot_emotion,
                "play_rain": play_rain # Add flag for rain sound
            }
            return jsonify(response_data)

        except Exception as e:
            current_app.logger.error(f"Error during AJAX chat processing: {e}") # Use current_app logger
            return jsonify({"error": "Sorry, I encountered an issue processing your message."}), 500

    return render_template('chat.html',
                           chat_history=current_history,
                           username=current_user.username)
