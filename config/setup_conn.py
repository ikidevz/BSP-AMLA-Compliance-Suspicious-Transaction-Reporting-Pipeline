import os
import subprocess


def add_connection(conn_id, command):
    try:
        print(f"➕ Adding connection '{conn_id}'...")
        result = subprocess.run(command, check=True,
                                capture_output=True, text=True)
        print(f"✅ '{conn_id}' added successfully!")
        print(result.stdout)

    except subprocess.CalledProcessError as e:
        if "already exists" in (e.stderr or ""):
            print(
                f"⚠️  '{conn_id}' already exists — deleting and recreating...")
            subprocess.run(["airflow", "connections",
                           "delete", conn_id], check=True)
            subprocess.run(command, check=True)
            print(f"✅ '{conn_id}' updated successfully!")
        else:
            print(f"❌ Error adding '{conn_id}': {e.stderr}")
            raise


if __name__ == "__main__":
    print("=" * 50)
    print("🔌 AIRFLOW CONNECTION SETUP")
    print("=" * 50)

    conn_id = os.getenv("DBT_POSTGRES_CONN_ID", "bsp_aml_pipeline_db")

    command = [
        "airflow", "connections", "add", conn_id,
        "--conn-type",     "postgres",
        "--conn-host",     os.getenv("DBT_POSTGRES_HOST",     "postgres"),
        "--conn-login",    os.getenv("DBT_POSTGRES_USER",     "airflow"),
        "--conn-password", os.getenv("DBT_POSTGRES_PASSWORD", "airflow"),
        "--conn-schema",   os.getenv("DBT_POSTGRES_DBNAME", "landed_cost_db"),
        "--conn-port",     os.getenv("DBT_POSTGRES_PORT",     "5432"),
    ]

    add_connection(conn_id, command)

    print("=" * 50)
    print("✅ Done")
    print("=" * 50)
