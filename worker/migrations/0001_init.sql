-- Players own a gamer tag. The token is the only proof of ownership and is
-- stored hashed. Nothing else about a person is kept.
CREATE TABLE IF NOT EXISTS players (
  id TEXT PRIMARY KEY,
  tag TEXT NOT NULL,
  tag_key TEXT NOT NULL UNIQUE,
  token_hash TEXT NOT NULL UNIQUE,
  best INTEGER NOT NULL DEFAULT 0,
  games INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);

-- One row per finished game.
CREATE TABLE IF NOT EXISTS scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id TEXT NOT NULL REFERENCES players(id),
  score INTEGER NOT NULL,
  lines INTEGER NOT NULL DEFAULT 0,
  max_combo INTEGER NOT NULL DEFAULT 0,
  moves INTEGER NOT NULL DEFAULT 0,
  duration_s INTEGER NOT NULL DEFAULT 0,
  played_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS scores_score ON scores(score DESC);
CREATE INDEX IF NOT EXISTS scores_played ON scores(played_at DESC, score DESC);
CREATE INDEX IF NOT EXISTS scores_player ON scores(player_id, score DESC);
CREATE INDEX IF NOT EXISTS players_best ON players(best DESC);
