import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
test_config = tomllib.loads((ROOT / "wrangler.test.toml").read_text())
prod_config = tomllib.loads((ROOT / "wrangler.toml").read_text())

test_db = test_config["d1_databases"][0]
prod_db = prod_config["d1_databases"][0]

assert test_config["name"] == "barq-api-phase2-test"
assert test_config["name"] != prod_config["name"]
assert test_config["main"] == prod_config["main"]
assert test_db["migrations_dir"] == "migrations"
assert prod_db["migrations_dir"] == "migrations/production"
production_migrations = sorted(path.name for path in (ROOT / prod_config["migrations_dir"]).glob("*.sql"))
assert production_migrations == ["0001_recovery_codes.sql", "0002_revoked_sessions.sql"]
assert not any("preview" in name.lower() for name in production_migrations)
assert test_config["workers_dev"] is True
assert test_db["binding"] == "DB"
assert test_db["database_name"] == "barq-phase2-test-2026-11-20"
assert test_db["database_id"] == "5bfada32-4f9b-4edb-85dd-3b3b30ab73b0"
assert test_db["database_id"] != prod_db["database_id"]
assert test_db["database_id"] != "0db93afd-4bf5-4423-9e25-7a2f4f4bdbe0"
assert prod_db["database_name"] == "siraj-db"
assert test_config["vars"]["TIGRIS_BUCKET"] == "barq-preview-media"
assert test_config["vars"]["TIGRIS_BUCKET"] != prod_config["vars"]["TIGRIS_BUCKET"]
assert "routes" not in test_config, "Test config must not target production routes."
assert test_config["triggers"]["crons"] == ["*/15 * * * *"]
print("BARQ Preview config is isolated from production DB, media bucket, and routes.")
