# database.rb

require "pg"

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

  def load_folder(folder_id)
    sql = "SELECT * FROM folders WHERE id = $1;"
    result = query(sql, folder_id).first
  end

  def create_folder(name, type, attr1, value1, attr2, value2, attr3, value3, user_id)
    sql_new_folder = "INSERT INTO folders (name, type, user_id) VALUES ($1, $2, $3);"
    query(sql_new_folder, name, type, user_id)

    sql_folder_id = "SELECT id FROM folders WHERE user_id = $1 AND name = $2"
    folder_id = query(sql_folder_id, user_id, name).first["id"].to_i

    sql_new_attrs = <<~SQL
      INSERT INTO attributes (name, value, folder_id)
      VALUES ($1, $2, $7), ($3, $4, $7), ($5, $6, $7);
    SQL
    query(sql_new_attrs, attr1, value1, attr2, value2, attr3, value3, folder_id)

    folder_id
  end

  private

  def query(statement, *params)
    logger.info "#{statement}: #{params}"
    db.exec_params(statement, params)
  end
end
