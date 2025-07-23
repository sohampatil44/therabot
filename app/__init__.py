from flask import Flask
from flask_login import LoginManager
import os
import datetime

# File-based SQLite database
DATABASE = 'therabot.db'

def create_app():
    app = Flask(__name__, instance_relative_config=True)

    # Create the instance folder if it doesn't exist
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    # Configuration for local development
    app.config.from_mapping(
        SECRET_KEY='local-therabot-secret-key-dev',
        DATABASE=os.path.join(app.instance_path, DATABASE)
    )

    # --- Initialize Flask-Login ---
    login_manager = LoginManager()
    login_manager.login_view = 'main.login'
    login_manager.login_message = "Please log in to access this page."
    login_manager.login_message_category = "info"
    login_manager.init_app(app)

    # --- Register database functions ---
    from . import db
    db.init_app(app)

    # --- User Loader for Flask-Login ---
    from .models import User

    @login_manager.user_loader
    def load_user(user_id):
        from flask import g  # ensure context
        conn = db.get_db()
        user_data = conn.execute(
            'SELECT * FROM users WHERE id = ?', (user_id,)
        ).fetchone()
        if user_data:
            return User(user_data['id'], user_data['username'], user_data['password'])
        return None

    # --- Register Blueprints ---
    from . import routes
    app.register_blueprint(routes.main)

    # --- Inject current year in templates ---
    @app.context_processor
    def inject_current_year():
        now = datetime.datetime.utcnow()
        return {'current_year': now.year}

    print(f"[Flask] App created successfully for LOCAL development")
    print(f"[DB] SQLite DB path: {app.config['DATABASE']}")
    
    return app
