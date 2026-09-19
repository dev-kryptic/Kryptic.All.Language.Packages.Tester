#!/bin/bash
set -euo pipefail
# Official image defaults to AllowAll*. Dynamic secrets need login roles.
sed -i \
  -e 's/AllowAllAuthenticator/PasswordAuthenticator/g' \
  -e 's/AllowAllAuthorizer/CassandraAuthorizer/g' \
  /etc/cassandra/cassandra.yaml
exec docker-entrypoint.sh cassandra -f
