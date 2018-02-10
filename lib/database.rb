# database.rb

require "pg"
require "pry"

class Database
  attr_reader :db, :logger

  def initialize(logger)
    @db = if Sinatra::Base.production?
            PG.connect(ENV['DATABASE_URL'])
          else
            PG.connect(dbname: "rnote")
          end
    @logger = logger
  end

  def disconnect
    @db.close
  end

  def load_folder(user_id, folder_id)
    sql = <<~SQL
      SELECT folders.name AS folder_name, folders.type AS folder_type, attributes.name AS attr_name, attributes.value AS attr_value
      FROM folders
      LEFT OUTER JOIN attributes ON folders.id = attributes.folder_id
      WHERE folders.user_id = $1 AND folders.id = $2;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        folder_name: tuple["folder_name"],
        folder_type: tuple["folder_type"],
        attr_name: tuple["attr_name"],
        attr_value: tuple["attr_value"]
      }
    end
  end

  def create_folder(name, type, attr1, value1, attr2, value2, attr3, value3, user_id)
    sql_new_folder = "INSERT INTO folders (name, type, user_id) VALUES ($1, $2, $3);"
    query(sql_new_folder, name, type, user_id)

    sql_folder_id = "SELECT id FROM folders WHERE user_id = $1 AND name = $2"
    folder_id = query(sql_folder_id, user_id, name).first["id"].to_i

    sql_attr_1 = <<~SQL
      INSERT INTO attributes (name, value, position, folder_id)
      VALUES ($1, $2, $3, $4);
    SQL
    query(sql_attr_1, attr1, value1, 1, folder_id)

    sql_attr_2 = <<~SQL
      INSERT INTO attributes (name, value, position, folder_id)
      VALUES ($1, $2, $3, $4);
    SQL
    query(sql_attr_2, attr2, value2, 2, folder_id)

    sql_attr_3 = <<~SQL
      INSERT INTO attributes (name, value, position, folder_id)
      VALUES ($1, $2, $3, $4);
    SQL
    query(sql_attr_3, attr3, value3, 3, folder_id)

    folder_id
  end

  def update_folder(user_id, folder_id, folder_name, folder_type, attr1, value1, attr2, value2, attr3, value3)
    sql_folder = "UPDATE folders SET (name, type) = ($1, $2) WHERE id = $3 AND user_id = $4;"
    query(sql_folder, folder_name, folder_type, folder_id, user_id)

    sql_attr1 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 1 AND folder_id = $3;"
    query(sql_attr1, attr1, value1, folder_id)

    sql_attr2 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 2 AND folder_id = $3;"
    query(sql_attr2, attr2, value2, folder_id)

    sql_attr3 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 3 AND folder_id = $3;"
    query(sql_attr3, attr3, value3, folder_id)
  end

  def load_notes(user_id, folder_id)
    sql = <<~SQL
      SELECT id AS note_id, title AS note_title, body AS note_body, dt AS note_date_time
      FROM notes
      WHERE user_id = $1 AND folder_id = $2;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        note_id: tuple["note_id"],
        note_title: tuple["note_title"],
        note_body: tuple["note_body"],
        note_date_time: tuple["note_date_time"]
      }
    end
  end

  def create_note(title, body, user_id, folder_id)
    sql = <<~SQL
      INSERT INTO notes (title, body, user_id, folder_id)
      VALUES ($1, $2, $3, $4);
    SQL

    query(sql, title, body, user_id, folder_id)
  end

  def update_note(user_id, folder_id, note_id, note_title, note_body)
    sql = <<~SQL
      UPDATE notes SET (title, body) = ($1, $2) WHERE id = $3 AND folder_id = $4 AND user_id = $5;
    SQL
    query(sql, note_title, note_body, note_id, folder_id, user_id)
  end

  private

  def query(statement, *params)
    logger.info "#{statement}: #{params}"
    db.exec_params(statement, params)
  end
end
