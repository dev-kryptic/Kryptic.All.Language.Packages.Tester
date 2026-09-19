CREATE KEYSPACE IF NOT EXISTS kryptic_dynamic_secrets_test
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE ROLE IF NOT EXISTS kryptic WITH PASSWORD = 'kryptic' AND LOGIN = true AND SUPERUSER = true;
