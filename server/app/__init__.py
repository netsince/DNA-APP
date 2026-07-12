from flask import Flask, jsonify
from flask_cors import CORS
from flask_migrate import Migrate

from app.config.settings import Config
from app.models import db
from app.routes.auth import auth_bp
from app.routes.health import health_bp


def _cors_origins():
    raw = Config.CORS_ORIGINS
    if not raw or raw.strip() == "*":
        return "*"
    return [o.strip() for o in raw.split(",") if o.strip()]


def create_app(config=Config):
    app = Flask(__name__)
    app.config.from_object(config)

    db.init_app(app)
    Migrate(app, db)
    CORS(app, resources={r"/api/*": {"origins": _cors_origins()}})

    app.register_blueprint(health_bp)
    app.register_blueprint(auth_bp)

    @app.errorhandler(404)
    def not_found(_e):
        return jsonify(error="not_found"), 404

    @app.errorhandler(405)
    def method_not_allowed(_e):
        return jsonify(error="method_not_allowed"), 405

    @app.errorhandler(500)
    def server_error(_e):
        return jsonify(error="internal_error"), 500

    return app
