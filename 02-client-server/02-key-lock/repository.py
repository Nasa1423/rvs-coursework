"""PostgreSQL state repository. Lock the input and its successor in ascending order."""
import os
import pg8000.dbapi

SCHEMA = """
CREATE TABLE IF NOT EXISTS number_state(
 number bigint PRIMARY KEY CHECK(number>=0), accepted boolean NOT NULL
);
CREATE TABLE IF NOT EXISTS request_history(
 request_id uuid PRIMARY KEY, number bigint NOT NULL,
 outcome text NOT NULL CHECK(outcome IN ('OK','DUPLICATE_NUMBER','PREDECESSOR_OF_PROCESSED')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE VIEW processed_numbers AS SELECT number FROM number_state WHERE accepted;
"""

class NumberRepository:
    def connect(self):
        return pg8000.dbapi.connect(host=os.getenv('DB_HOST','127.0.0.1'),
            port=int(os.getenv('DB_PORT','54329')), database=os.getenv('DB_NAME','postgres'),
            user=os.getenv('DB_USER','student'), password=os.getenv('DB_PASSWORD',''),timeout=5)

    def initialize(self):
        conn=self.connect()
        try:
            cur=conn.cursor()
            for statement in SCHEMA.split(';'):
                if statement.strip():cur.execute(statement)
            conn.commit()
        finally:conn.close()

    def health(self):
        conn=self.connect()
        try:
            cur=conn.cursor()
            cur.execute('SELECT number FROM number_state LIMIT 0')
            cur.execute('SELECT request_id FROM request_history LIMIT 0')
        finally:conn.close()

    def process(self,number,request_id):
        conn=self.connect()
        try:
            cur=conn.cursor()
            cur.execute('SET TRANSACTION ISOLATION LEVEL READ COMMITTED')
            cur.execute("SET LOCAL lock_timeout = '3s'")
            cur.execute("SET LOCAL statement_timeout = '3s'")
            # Adjacent requests share one key; distant requests need not serialize.
            # Ascending acquisition order avoids a cycle of advisory locks.
            for key in (number,number+1):
                cur.execute('SELECT pg_advisory_xact_lock(CAST(%s AS bigint))',(key,))
            cur.execute('SELECT accepted FROM number_state WHERE number=%s',(number,))
            seen=cur.fetchone()
            if seen is not None:
                outcome='DUPLICATE_NUMBER'
            else:
                cur.execute('SELECT accepted FROM number_state WHERE number=%s',(number+1,))
                successor=cur.fetchone()
                accepted=successor is None or not successor[0]
                outcome='OK' if accepted else 'PREDECESSOR_OF_PROCESSED'
                cur.execute('INSERT INTO number_state(number,accepted) VALUES(%s,%s)',(number,accepted))
            cur.execute('INSERT INTO request_history(request_id,number,outcome) VALUES(%s,%s,%s)',
                        (request_id,number,outcome))
            conn.commit()
            return outcome
        except Exception:
            conn.rollback()
            raise
        finally:conn.close()

repository=NumberRepository()
