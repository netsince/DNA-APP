from flask import Flask

from app.config.settings import Config
from app.routes.health import health_bp


def create_app(config=Config):
    app = Flask(__name__)
    app.config.from_object(config)
    app.register_blueprint(health_bp)
    return app
