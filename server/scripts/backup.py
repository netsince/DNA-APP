"""本地全量备份 DNA 数据库到 backups/ 下的 SQL 文件。

凭据从 .env 读取，不在此处硬编码。运行：uv run python scripts/backup.py
"""
import os
import sys
from datetime import datetime
from pathlib import Path

import pymysql

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config.settings import Config


def _escape(value):
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, bytes):
        return "'" + value.decode("utf-8", "replace").replace("'", "''") + "'"
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


def main():
    conn = pymysql.connect(
        host=Config.DB_HOST,
        port=Config.DB_PORT,
        user=Config.DB_USER,
        password=Config.DB_PASSWORD,
        database=Config.DB_NAME,
        charset="utf8mb4",
    )
    out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backups"))
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = os.path.join(out_dir, f"backup_{Config.DB_NAME}_{stamp}.sql")

    with conn.cursor() as cur:
        cur.execute("SHOW TABLES")
        tables = [r[0] for r in cur.fetchall()]
        lines = [f"-- DNA DB backup {stamp}", f"-- database: {Config.DB_NAME}", ""]
        for table in tables:
            cur.execute(f"SHOW CREATE TABLE `{table}`")
            create_sql = cur.fetchone()[1]
            lines.append(f"DROP TABLE IF EXISTS `{table}`;")
            lines.append(create_sql + ";")
            cur.execute(f"SELECT * FROM `{table}`")
            cols = [d[0] for d in cur.description]
            for row in cur.fetchall():
                vals = ", ".join(_escape(v) for v in row)
                col_str = ", ".join(f"`{c}`" for c in cols)
                lines.append(f"INSERT INTO `{table}` ({col_str}) VALUES ({vals});")
            lines.append("")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    conn.close()
    print(f"备份完成：{out_path}（共 {len(tables)} 张表）")


if __name__ == "__main__":
    main()
