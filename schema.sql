set time zone 'UTC';

CREATE TABLE users (
  id serial PRIMARY KEY,
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  password text NOT NULL,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE folders (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  type text NOT NULL,
  user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notes (
  id serial PRIMARY KEY,
  title text NOT NULL,
  body text,
  user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  folder_id integer NOT NULL REFERENCES folders (id) ON DELETE CASCADE,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE attributes (
  id serial PRIMARY KEY,
  name text NOT NULL,
  value text NOT NULL,
  position integer NOT NULL,
  folder_id integer NOT NULL REFERENCES folders (id) ON DELETE CASCADE,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE relations (
  id serial PRIMARY KEY,
  parent_id integer NOT NULL REFERENCES folders (id) ON DELETE CASCADE,
  child_id integer REFERENCES folders (id) ON DELETE CASCADE,
  dt timestamptz NOT NULL DEFAULT now(),
  UNIQUE (parent_id, child_id)
);

INSERT INTO users (name, email, password) VALUES ('Jason', 'jason@gmail.com', 'secret');
