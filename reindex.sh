#!/bin/bash
set -e

WORKING_DIR="./state"
DOWNLOAD_DIR="./complete"
DB_CONN="postgresql://penumbra:yourpassword@localhost:5432/penumbra"

mkdir -p $DOWNLOAD_DIR
mkdir -p $WORKING_DIR

cd $DOWNLOAD_DIR

wget -nc https://artifacts.plinfra.net/penumbra-1/reindexer_archive-height-501974.sqlite
wget -nc https://artifacts.plinfra.net/penumbra-1/reindexer_archive-height-2611800.sqlite3
wget -nc https://artifacts.plinfra.net/penumbra-1/reindexer_archive-height-4504015.sqlite

cd ..

penumbra-reindexer regen \
  --database-url "$DB_CONN" \
  --working-dir "$WORKING_DIR" \
  --archive-file "$DOWNLOAD_DIR/reindexer_archive-height-501974.sqlite" \
  --stop-height 501974

penumbra-reindexer regen \
  --database-url "$DB_CONN" \
  --working-dir "$WORKING_DIR" \
  --archive-file "$DOWNLOAD_DIR/reindexer_archive-height-2611800.sqlite3" \
  --start-height 501975 \
  --stop-height 2611800

penumbra-reindexer regen \
  --database-url "$DB_CONN" \
  --working-dir "$WORKING_DIR" \
  --archive-file "$DOWNLOAD_DIR/reindexer_archive-height-4504015.sqlite" \
  --start-height 2611801 \
  --stop-height 4504015

psql "$DB_CONN" -c "SELECT MIN(height), MAX(height) FROM blocks;"

echo "Reindexing completed. You now have data from height 0 to 4504015."
echo "Set up your node to use this database with the following settings in cometbft/config/config.toml:"
echo ""
echo "[tx_index]"
echo "indexer = \"psql\""
echo "psql-conn = \"$DB_CONN\""
