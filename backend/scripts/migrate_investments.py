import sqlite3
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def migrate():
    db_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'finance_tracker.db')
    if not os.path.exists(db_path):
        logger.error(f"Database not found at {db_path}")
        return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        # 1. Create asset_classes table if not exists
        logger.info("Creating asset_classes table...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS asset_classes (
                id INTEGER PRIMARY KEY,
                name VARCHAR(100) NOT NULL UNIQUE,
                color_hex VARCHAR(7) NOT NULL DEFAULT '#4CAF50',
                icon_name VARCHAR(50) NOT NULL DEFAULT 'account_balance_wallet'
            )
        """)

        # 2. Check if investment_rules has asset_class_id already
        cursor.execute("PRAGMA table_info(investment_rules)")
        columns = [col[1] for col in cursor.fetchall()]
        if 'asset_class_id' in columns:
            logger.info("Migration already applied (asset_class_id exists).")
            return

        # 3. Seed asset classes from existing investment_rules
        logger.info("Seeding asset_classes...")
        cursor.execute("""
            INSERT OR IGNORE INTO asset_classes (name)
            SELECT DISTINCT asset_class FROM investment_rules
        """)
        
        # Also seed some defaults just in case
        defaults = ['Mutual Funds', 'Stocks', 'Fixed Deposits', 'Recurring Deposits', 'Insurance', 'Commodities (Gold/Silver)', 'Provident Funds', 'Bonds', 'Real Estate', 'Crypto', 'Other']
        for d in defaults:
            cursor.execute("INSERT OR IGNORE INTO asset_classes (name) VALUES (?)", (d,))

        # 4. Create new investment_rules table
        logger.info("Recreating investment_rules table...")
        cursor.execute("""
            CREATE TABLE investment_rules_new (
                id INTEGER PRIMARY KEY,
                platform_name VARCHAR(100) NOT NULL,
                asset_class_id INTEGER NOT NULL,
                keywords VARCHAR(500),
                FOREIGN KEY(asset_class_id) REFERENCES asset_classes(id)
            )
        """)

        # 5. Migrate data
        logger.info("Migrating data...")
        cursor.execute("""
            INSERT INTO investment_rules_new (id, platform_name, asset_class_id, keywords)
            SELECT i.id, i.platform_name, a.id, i.keywords
            FROM investment_rules i
            JOIN asset_classes a ON i.asset_class = a.name
        """)

        # 6. Swap tables
        logger.info("Swapping tables...")
        cursor.execute("DROP TABLE investment_rules")
        cursor.execute("ALTER TABLE investment_rules_new RENAME TO investment_rules")

        conn.commit()
        logger.info("Migration completed successfully!")

    except Exception as e:
        conn.rollback()
        logger.error(f"Migration failed: {e}")
        raise
    finally:
        conn.close()

if __name__ == '__main__':
    migrate()
