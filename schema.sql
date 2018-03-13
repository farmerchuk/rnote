set time zone 'UTC';

CREATE TABLE users (
  id serial PRIMARY KEY,
  uuid uuid UNIQUE NOT NULL,
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  password text NOT NULL,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE folders (
  id serial PRIMARY KEY,
  uuid uuid UNIQUE NOT NULL,
  name text UNIQUE NOT NULL,
  tags text NOT NULL CHECK (tags ~ '^[a-z0-9 _-]+$'),
  user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  dt timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notes (
  id serial PRIMARY KEY,
  uuid uuid UNIQUE NOT NULL,
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

INSERT INTO users (name, uuid, email, password) VALUES ('Jason', '1c5a3880-0625-0136-c75a-784f43a699ea', 'jason@gmail.com', 'secret');
