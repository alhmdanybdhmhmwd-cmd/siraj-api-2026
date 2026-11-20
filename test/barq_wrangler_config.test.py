import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
test_config = tomllib.loads((ROOT / "wrangler.test.toml").read_text())
prod_config = tomllib.loads((ROOT / "wrangler.toml").read_text())

test_db = test_config["d1_databases"][0]
prod_db = prod_config["d1_databases"][0]

assert test_config["name"] == "barq-api-phase2-test"
assert test_config["main"] == prod_config["main"]
assert test_db["binding"] == "DB"
assert test_db["database_name"] == "barq-phase2-test-2026-11-20"
assert test_db["database_id"] == "5bfada32-4f9b-4edb-85dd-3b3b30ab73b0"
assert test_db["database_id"] != prod_db["database_id"]
assert prod_db["database_name"] == "siraj-db"
assert "vars" not in test_config, "Test config must not inherit production variables."
assert "routes" not in test_config, "Test config must not target production routes."
print("BARQ test Wrangler config is isolated from production.")
