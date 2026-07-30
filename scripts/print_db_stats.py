#!/usr/bin/env python3
"""输出 offline_content.db 的统计信息"""
import sqlite3, sys

db_path = sys.argv[1] if len(sys.argv) > 1 else 'offline_content.db'
conn = sqlite3.connect(db_path)

# 构建元数据
rows = conn.execute('SELECT key, value FROM build_meta').fetchall()
print('构建元数据:')
for k, v in rows:
    print(f'  {k}: {v}')
print()

# 内容统计
rows2 = conn.execute('''
    SELECT scp_type, COUNT(*) as cnt,
           ROUND(SUM(compressed_size)/1024.0/1024.0, 1) as comp_mb
    FROM pages GROUP BY scp_type ORDER BY cnt DESC
''').fetchall()
total_pages = sum(r[1] for r in rows2)
total_mb = sum(r[2] for r in rows2)
print(f'内容统计: {total_pages} 页, {total_mb:.1f}MB')
for tp, cnt, mb in rows2:
    print(f'  type {tp:2d}: {cnt:5d} 页, {mb:.1f}MB')

conn.close()
