import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    HOST = os.environ.get("HOST", "0.0.0.0")
    PORT = int(os.environ.get("PORT", "5011"))
    DEBUG = os.environ.get("FLASK_DEBUG", "False").lower() in ("true", "1", "t")
    SECRET_KEY = os.environ.get("SECRET_KEY", "")
    APPNAME = os.environ.get("APPNAME", "dna-server")

    DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
    DB_PORT = int(os.environ.get("DB_PORT", "3306"))
    DB_USER = os.environ.get("DB_USER", "dna")
    DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
    DB_NAME = os.environ.get("DB_NAME", "dna")
    SQLALCHEMY_DATABASE_URI = (
        f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}?charset=utf8mb4"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
    SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
    SMTP_USER = os.environ.get("SMTP_USER", "")
    SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
    SMTP_FROM = os.environ.get("SMTP_FROM", "")

    CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "*")
    TOKEN_MAX_AGE = int(os.environ.get("TOKEN_MAX_AGE", "86400"))
    PASSWORD_MIN_LENGTH = int(os.environ.get("PASSWORD_MIN_LENGTH", "8"))
