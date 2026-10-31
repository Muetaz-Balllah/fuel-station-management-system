import os

os.environ["DATABASE_URL"] = "sqlite://"
os.environ["REDIS_URL"] = "memory"
os.environ["JWT_SECRET"] = "test-secret-key-at-least-32-characters-long"
os.environ["SEED_ON_STARTUP"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["SEED_MANAGER_USERNAME"] = "manager"
os.environ["SEED_MANAGER_PASSWORD"] = "Manager@12345"
os.environ["SEED_OPERATOR_USERNAME"] = "operator"
os.environ["SEED_OPERATOR_PASSWORD"] = "Operator@12345"
os.environ["LOCKOUT_ATTEMPTS"] = "5"
os.environ["LOCKOUT_MINUTES"] = "15"
