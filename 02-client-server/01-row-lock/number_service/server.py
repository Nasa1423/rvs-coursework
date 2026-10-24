"""Application server. Business checks and history are one PostgreSQL transaction."""
import argparse
import json
import logging
import sys
import os
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import pg8000.dbapi

MAX_BODY = 4096
SCHEMA = '''
CREATE TABLE IF NOT EXISTS processing_guard(id integer PRIMARY KEY CHECK(id=1));
INSERT INTO processing_guard VALUES(1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS processed_numbers(
    number bigint PRIMARY KEY CHECK(number>=0),
    processed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS request_history(
    request_id uuid PRIMARY KEY,
    number bigint NOT NULL,
    outcome text NOT NULL CHECK(outcome IN ('OK','DUPLICATE_NUMBER','PREDECESSOR_OF_PROCESSED')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS history_number ON request_history(number);
'''

def connect_database():
    return pg8000.dbapi.connect(host=os.getenv('DB_HOST','127.0.0.1'),
        port=int(os.getenv('DB_PORT','54329')),database=os.getenv('DB_NAME','postgres'),
        user=os.getenv('DB_USER','student'),password=os.getenv('DB_PASSWORD',''),timeout=5)

def initialize_schema():
    conn = connect_database()
    try:
        cursor = conn.cursor()
        for statement in SCHEMA.split(';'):
            if statement.strip(): cursor.execute(statement)
        conn.commit()
    finally: conn.close()

def evaluate_number(number, request_id):
    conn = connect_database()
    try:
        cur = conn.cursor()
        cur.execute('SET TRANSACTION ISOLATION LEVEL READ COMMITTED')
        cur.execute("SET LOCAL lock_timeout = '3s'")
        cur.execute("SET LOCAL statement_timeout = '3s'")
        cur.execute('SELECT id FROM processing_guard WHERE id=1 FOR UPDATE')
        if cur.fetchone() is None: raise RuntimeError('Missing processing guard')
        # New statement after acquiring the lock sees the preceding commit.
        cur.execute('SELECT EXISTS(SELECT 1 FROM request_history WHERE number=%s)',(number,))
        if cur.fetchone()[0]: outcome = 'DUPLICATE_NUMBER'
        else:
            cur.execute('SELECT EXISTS(SELECT 1 FROM processed_numbers WHERE number=%s)',(number+1,))
            if cur.fetchone()[0]: outcome = 'PREDECESSOR_OF_PROCESSED'
            else:
                cur.execute('INSERT INTO processed_numbers(number) VALUES(%s)',(number,))
                outcome = 'OK'
        cur.execute('INSERT INTO request_history(request_id,number,outcome) VALUES(%s,%s,%s)',
                    (request_id,number,outcome))
        conn.commit()
        return outcome
    except Exception:
        conn.rollback()
        raise
    finally: conn.close()

def unique_object(pairs):
    obj = {}
    for key,value in pairs:
        if key in obj: raise ValueError('Duplicate JSON key')
        obj[key]=value
    return obj

class Handler(BaseHTTPRequestHandler):
    server_version = 'NumbersApp/1.0'
    def setup(self):
        super().setup(); self.connection.settimeout(6)
    def log_message(self,*args): pass
    def send_json(self,status,payload):
        data=json.dumps(payload,ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(data)))
        self.send_header('Cache-Control','no-store')
        self.end_headers(); self.wfile.write(data)
    def error(self,status,code,request_id,**context):
        logging.error(json.dumps({'request_id':request_id,'error':code,**context},ensure_ascii=False))
        self.send_json(status,{'error':code,'request_id':request_id})
    def do_GET(self):
        if self.path!='/health': return self.send_json(404,{'error':'NOT_FOUND'})
        try:
            conn=connect_database()
            try:
                cur=conn.cursor();cur.execute('SELECT id FROM processing_guard WHERE id=1')
                if cur.fetchone() is None: raise RuntimeError('Schema not initialized')
            finally: conn.close()
        except Exception: return self.send_json(503,{'status':'unavailable'})
        self.send_json(200,{'status':'ok','max_number':self.server.max_number})
    def do_POST(self):
        request_id=str(uuid.uuid4())
        if self.path!='/increment': return self.error(404,'NOT_FOUND',request_id)
        try:
            if self.headers.get('Transfer-Encoding'): raise ValueError('Transfer coding not supported')
            length=int(self.headers.get('Content-Length','-1'))
            if not 0 < length <= MAX_BODY: raise ValueError('Body size')
            if self.headers.get('Content-Type','').split(';')[0].strip().lower()!='application/json':
                raise ValueError('Content type')
            raw=self.rfile.read(length)
            if len(raw)!=length: raise ValueError('Truncated body')
            obj=json.loads(raw.decode('utf-8'),object_pairs_hook=unique_object)
            if not isinstance(obj,dict) or set(obj)!={'number'}: raise ValueError('Object fields')
            number=obj['number']
            if type(number) is not int or not 0 <= number <= self.server.max_number:
                raise ValueError('Number type or range')
        except (ValueError,UnicodeError,TimeoutError,OSError):
            return self.error(400,'INVALID_INPUT',request_id)
        try: outcome=evaluate_number(number,request_id)
        except Exception as exc:
            return self.error(503,'DATABASE_UNAVAILABLE',request_id,exception=type(exc).__name__)
        if outcome!='OK': return self.error(409,outcome,request_id,number=number)
        logging.info(json.dumps({'request_id':request_id,'outcome':'OK','number':number}))
        self.send_json(200,{'result':number+1,'request_id':request_id})

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--host',default=os.getenv('APP_HOST','127.0.0.1'))
    parser.add_argument('--port',type=int,default=int(os.getenv('APP_PORT','8081')))
    parser.add_argument('--max-number',type=int,default=int(os.getenv('MAX_NUMBER','1000000')))
    parser.add_argument('--init-db',action='store_true')
    args=parser.parse_args()
    if not 0 <= args.max_number <= 9223372036854775806: parser.error('MAX_NUMBER outside bigint range')
    logging.basicConfig(stream=sys.stdout,level=logging.INFO,format='%(message)s',force=True)
    if args.init_db: initialize_schema()
    server=ThreadingHTTPServer((args.host,args.port),Handler);server.daemon_threads=True
    server.max_number=args.max_number
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
