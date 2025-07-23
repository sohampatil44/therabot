import json
import os
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer
from sentence_transformers import SentenceTransformer, util
import google.generativeai as genai  # Added import
from dotenv import load_dotenv  # Added import

# Global variable for the Gemini model
gemini_model = None
THERABOT_SYSTEM_PROMPT = ""  # Keep this global for the prompt structure


def detect_emotion(text: str) -> str:
    try:
        tokenizer = AutoTokenizer.from_pretrained("tabularisai/multilingual-sentiment-analysis")
        model = AutoModelForSequenceClassification.from_pretrained("tabularisai/multilingual-sentiment-analysis")
        inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
        outputs = model(**inputs)
        pred_id = torch.argmax(outputs.logits, dim=1).item()

        emotion_map = {0: "sad", 1: "neutral", 2: "happy", 3: "angry", 4: "worried"}
        prediction = emotion_map.get(pred_id, "neutral")

        print(f"Detected emotion: {prediction}")
        return prediction
    except Exception as e:
        print(f"Error in emotion detection: {e}")
        return fallback_emotion_detection(text)


def fallback_emotion_detection(text: str) -> str:
    keywords = {
        "happy": ["happy", "joy", "excited", "great", "excellent", "good"],
        "sad": ["sad", "depressed", "upset", "down", "lonely", "miserable"],
        "angry": ["angry", "frustrated", "mad", "annoyed", "irritated", "pissed"],
        "worried": ["worried", "anxious", "concern", "nervous", "stressed", "scared"],
        "neutral": ["think", "consider", "maybe", "perhaps", "wonder", "know", "tell"]
    }
    text_lower = text.lower()
    for emotion in ["angry", "sad", "worried", "happy", "neutral"]:
        if any(word in text_lower for word in keywords[emotion]):
            return emotion
    return "neutral"


def load_models():
    load_dotenv()  # Load environment variables from .env file
    global gemini_model  # Use global model variable
    try:
        print("Loading models...")
        embedder = SentenceTransformer("paraphrase-MiniLM-L3-v2")

        # Configure Gemini API
        google_api_key = os.getenv("GOOGLE_API_KEY")
        if not google_api_key:
            print("ERROR: GOOGLE_API_KEY environment variable not set.")
            exit(1)
        genai.configure(api_key=google_api_key)

        # Initialize Gemini model
        gemini_model = genai.GenerativeModel('gemini-1.5-flash-latest')  # Assign to global variable

        global THERABOT_SYSTEM_PROMPT
        THERABOT_SYSTEM_PROMPT = (
            "You are Therabot, a dedicated mental health assistant. Your primary function is to provide empathetic "
            "support, guidance, and a listening ear regarding emotional and mental wellbeing. "
            "Analyze the user's input for emotional context and respond genuinely and supportively. "
            "When appropriate, especially when discussing feelings or if the user asks for help, provide thoughtful explanations or suggest potential coping strategies or perspectives. Aim for helpful and considerate responses.\n\n"
            # --- Added instruction about username ---
            "The user you are speaking with is named {username}. Address them by their name occasionally, where it feels natural and supportive (e.g., 'That sounds tough, {username}.', or 'How does that make you feel, {username}?'). Do not overuse the name.\n\n"
            # --- Guideline (Keep as is) ---
            "GUIDELINE: While your focus is mental health, you can briefly acknowledge related context if helpful. "
            "However, if the user's input shifts significantly away from personal feelings, emotions, or wellbeing "
            "(e.g., asking for detailed information on unrelated topics like history, science, coding, recipes, politics), "
            "gently steer the conversation back or politely state that the topic is outside your scope of expertise as a mental health assistant. "
            "Avoid abrupt refusals for slightly related questions, but maintain your core focus. Example refusal: 'My expertise is in mental wellbeing, so I can't help with that specific topic. How are you feeling today?'\n\n"
            # --- End Guideline ---
            "Your knowledge is centered on mental health. Prioritize empathetic listening and support."
        )
        print("Models loaded successfully (Embedder + Gemini configured)")
        return embedder, gemini_model
    except Exception as e:
        print(f"Error loading models or configuring Gemini: {e}")
        exit(1)


def load_knowledge_base():
    try:
        kb_path = "knowledge_base.json"
        if not os.path.exists(kb_path):
            print("Knowledge base not found. Creating a simple one...")
            sample_kb = [
                {"emotion": "happy", "text": "It's great to hear you're feeling positive!"},
                {"emotion": "sad", "text": "I'm sorry you're feeling down. Remember that it's okay to feel sad, and I'm here to listen."},
                {"emotion": "angry", "text": "Feeling angry is understandable sometimes. What's causing this frustration for you?"},
                {"emotion": "neutral", "text": "I see. Tell me more about what's on your mind."},
                {"emotion": "worried", "text": "It sounds like you're dealing with some worry. Let's talk through it."}
            ]
            with open(kb_path, "w") as f:
                json.dump(sample_kb, f, indent=4)

        with open(kb_path, "r") as f:
            knowledge_data = json.load(f)
        print(f"Loaded {len(knowledge_data)} entries from knowledge base")
        return knowledge_data
    except Exception as e:
        print(f"Error loading knowledge base: {e}")
        return [{"emotion": "neutral", "text": "I'm here to help."}]


def retrieve_context(user_input, emotion, corpus, corpus_embeddings, embedder, knowledge_data, k=1):
    try:
        emotion_texts = [entry["text"] for entry in knowledge_data if entry["emotion"] == emotion]
        relevant_corpus = emotion_texts or corpus

        if not relevant_corpus:
            return ["I'm here for you. Let's talk."]

        target_embeddings = (
            embedder.encode(relevant_corpus, convert_to_tensor=True)
            if emotion_texts or corpus_embeddings is None
            else corpus_embeddings
        )

        user_emb = embedder.encode(user_input, convert_to_tensor=True)
        scores = util.pytorch_cos_sim(user_emb, target_embeddings)
        actual_k = min(k, len(relevant_corpus))

        if actual_k == 0:
            return ["How does that make you feel?"]

        top_results = torch.topk(scores, k=actual_k)
        top_indices, top_scores = top_results[1][0], top_results[0][0]

        score_threshold = 0.3
        contexts = [relevant_corpus[idx] for i, idx in enumerate(top_indices) if top_scores[i] >= score_threshold]

        return contexts if contexts else ["Tell me more about that."]
    except Exception as e:
        print(f"Error retrieving context: {e}")
        return ["I'm here to listen and help you with your concerns."]


def build_prompt_user_part(user_input: str, emotion: str, context: list[str]) -> str:
    context_str = "\n".join(f"- {c}" for c in context) if context else "No specific context retrieved."
    return (
        f"User Input: {user_input}\n"
        f"Detected Emotion: {emotion}\n"
        f"Potentially Relevant Info:\n{context_str}\n"
        f"Assistant Response:"
    )


def generate_response(user_prompt_part: str, generator, username: str) -> str:  # Added username parameter
    global gemini_model
    if generator is None:
        print("Error: Gemini model not initialized.")
        return "Sorry, I encountered an issue. Please try again later."

    try:
        # Format the system prompt with the actual username
        formatted_system_prompt = THERABOT_SYSTEM_PROMPT.format(username=username)

        # Combine formatted system prompt and user part for Gemini
        full_prompt = f"{formatted_system_prompt}\n\n{user_prompt_part}"

        # Use the passed generator (Gemini model instance)
        response = generator.generate_content(full_prompt)

        if not response.parts:
            print("Warning: Gemini response has no parts.")
            try:
                if response.prompt_feedback.block_reason:
                    print(f"Content blocked due to: {response.prompt_feedback.block_reason}")
                    return "I cannot respond to that request as it may violate safety guidelines."
            except Exception:
                pass
            return "I'm having trouble formulating a response right now. Could you try rephrasing?"

        cleaned_response = response.text.strip()

        # Remove system prompt repetition if present (use the formatted one)
        if formatted_system_prompt in cleaned_response:
            cleaned_response = cleaned_response.replace(formatted_system_prompt, "")

        # Remove potential "Assistant Response:" prefix
        if "Assistant Response:" in cleaned_response:
            cleaned_response = cleaned_response.split("Assistant Response:")[-1].strip()

        if not cleaned_response:
            return "I'm listening. Could you elaborate a bit?"

        return cleaned_response
    except Exception as e:
        print(f"Error generating response with Gemini: {e}")
        return "I understand. Please know I'm here to listen, but I encountered an issue processing your request."
