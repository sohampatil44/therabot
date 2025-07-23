# run.py (or your main execution script)
from app import create_app

# Create the Flask app instance using the factory
app = create_app()

# Add any other local setup if needed

if __name__ == '__main__':
    # For local development, simply run with debug=True
    # This uses the default host '127.0.0.1' (localhost) and port 5000
    # It also enables the interactive debugger and automatic reloader
    print("Starting Flask app in LOCAL DEBUG mode on http://127.0.0.1:5000")
    app.run(debug=True)
    # The reloader might cause the AI models to load twice if 'load_models'
    # is called directly at the top level of routes.py. If this is an issue,
    # you might need to implement lazy loading or disable the reloader
    # temporarily (app.run(debug=True, use_reloader=False)), but the
    # reloader is very convenient for development.