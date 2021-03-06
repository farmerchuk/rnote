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

  # Helper methods

  def sort_folders(sort_method, folders)
    if sort_method == "recently_created_first" || sort_method == "recently_created_last"
      folders = sort_folders_by_created_date(folders)
      folders.reverse! if sort_method == "recently_created_first"
    end
    if sort_method == "alphabetical" || sort_method == "reverse_alphabetical"
      folders = sort_folders_alphabetically(folders)
      folders.reverse! if sort_method == "reverse_alphabetical"
    end

    folders
  end

  def sort_folders_by_created_date(folders)
    folders.sort_by { |folder| folder[:date_time] }
  end

  def sort_folders_alphabetically(folders)
    folders.sort_by { |folder| folder[:folder_name] }
  end

  # Database methods

  def get_user_by_email(email)
    email = email.downcase
    sql = "SELECT * FROM users WHERE email = $1;"
    result = query(sql, email)
    user = result.map do |tuple|
      {
        id: tuple["id"],
        uuid: tuple["uuid"],
        name: tuple["name"],
        email: tuple["email"],
        password: tuple["password"]
      }
    end

    user.empty? ? nil : user.first
  end

  def create_user(name, uuid, email, password)
    email = email.downcase
    sql = <<~SQL
      INSERT INTO users (name, uuid, email, password)
      VALUES ($1, $2, $3, $4);
    SQL
    query(sql, name, uuid, email, password)

    get_user_by_email(email)
  end

  def user_id_by_uuid(uuid)
    sql = "SELECT id FROM users WHERE uuid = $1;"
    result = query(sql, uuid)
    result.values.empty? ? nil : result.first['id']
  end

  def folder_id_by_uuid(uuid)
    sql = "SELECT id FROM folders WHERE uuid = $1;"
    result = query(sql, uuid)
    result.values.empty? ? nil : result.first['id']
  end

  def folder_name_by_id(folder_id)
    sql = "SELECT name FROM folders WHERE id = $1;"
    result = query(sql, folder_id)
    result.values.empty? ? nil : result.first['name']
  end

  def load_folder(user_id, folder_id)
    sql = <<~SQL
      SELECT folders.name AS folder_name, folders.tags AS folder_tags, attributes.name AS attr_name, attributes.value AS attr_value
      FROM folders
      LEFT OUTER JOIN attributes ON folders.id = attributes.folder_id
      WHERE folders.user_id = $1 AND folders.id = $2;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        folder_name: tuple["folder_name"],
        folder_tags: tuple["folder_tags"],
        attr_name: tuple["attr_name"],
        attr_value: tuple["attr_value"]
      }
    end
  end

  def load_folders(user_id, search_query, tag_filter, sort_method)
    search_query = "%" + search_query + "%"
    tag_filter = "%" + tag_filter + "%"

    sql = <<~SQL
      SELECT * FROM folders WHERE user_id = $1 AND name ILIKE $2 AND tags ILIKE $3;
    SQL

    result = query(sql, user_id, search_query, tag_filter)
    folders = result.map do |tuple|
      {
        folder_id: tuple["id"],
        folder_uuid: tuple["uuid"].delete('-'),
        folder_name: tuple["name"],
        folder_tags: tuple["tags"],
        date_time: tuple["dt"]
      }
    end

    sort_folders(sort_method, folders)
  end

  def load_linkable_folders(user_id, search_query, folder_id, tag_filter, sort_method)
    search_query = "%" + search_query + "%"
    tag_filter = "%" + tag_filter + "%"

    sql = <<~SQL
      SELECT * FROM folders
      WHERE NOT id = ANY (
        SELECT child_id FROM relations WHERE parent_id = $1 AND child_id IS NOT NULL
        UNION SELECT parent_id FROM relations WHERE child_id = $1 AND parent_id IS NOT NULL
        UNION SELECT $1)
      AND name ILIKE $2 AND tags ILIKE $3 AND user_id = $4;
    SQL

    result = query(sql, folder_id, search_query, tag_filter, user_id)
    folders = result.map do |tuple|
      {
        folder_id: tuple["id"],
        folder_uuid: tuple["uuid"].delete('-'),
        folder_name: tuple["name"],
        folder_tags: tuple["tags"],
        date_time: tuple["dt"]
      }
    end

    sort_folders(sort_method, folders)
  end

  def load_related_folders(user_id, folder_id)
    sql = <<~SQL
      SELECT id, uuid, name, tags FROM folders
      WHERE id = ANY (SELECT child_id FROM relations WHERE parent_id = $2) AND user_id = $1
      UNION
      SELECT id, uuid, name, tags FROM folders
      WHERE id = ANY (SELECT parent_id FROM relations WHERE child_id = $2) AND user_id = $1;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        folder_id: tuple["id"],
        folder_uuid: tuple["uuid"].delete('-'),
        folder_name: tuple["name"],
        folder_tags: tuple["tags"]
      }
    end
  end

  def load_related_folders_with_query(user_id, folder_id, search_query, tag_filter, sort_method)
    search_query = "%" + search_query + "%"
    tag_filter = "%" + tag_filter + "%"

    sql = <<~SQL
      SELECT id, uuid, name, tags FROM folders
      WHERE name ILIKE $3
      AND tags ILIKE $4
      AND id = ANY (
        SELECT child_id FROM relations
        WHERE parent_id = $2 AND user_id = $1
        UNION SELECT parent_id FROM relations
          WHERE child_id = $2 AND user_id = $1
      );
    SQL

    result = query(sql, user_id, folder_id, search_query, tag_filter)
    folders = result.map do |tuple|
      {
        folder_id: tuple["id"],
        folder_uuid: tuple["uuid"].delete('-'),
        folder_name: tuple["name"],
        folder_tags: tuple["tags"],
        date_time: tuple["dt"]
      }
    end

    sort_folders(sort_method, folders)
  end

  def load_folder_names_by_user(user_id)
    sql = "SELECT name FROM folders WHERE user_id = $1;"
    result = query(sql, user_id)
    result.map { |tuple| tuple["name"].downcase }
  end

  def link_folders(from_folder_id, to_folder_id)
    sql = "INSERT INTO relations (parent_id, child_id) VALUES ($1, $2);"
    query(sql, to_folder_id, from_folder_id);
  end

  def unlink_folders(from_folder_id, to_folder_id)
    sql = "DELETE FROM relations WHERE (parent_id = $1 AND child_id = $2) OR (child_id = $1 AND parent_id = $2);"
    query(sql, to_folder_id, from_folder_id);
  end

  def create_folder(name, tags, attr1, value1, attr2, value2, attr3, value3, user_id, uuid)
    sql_new_folder = "INSERT INTO folders (name, tags, user_id, uuid) VALUES ($1, $2, $3, $4);"
    query(sql_new_folder, name, tags, user_id, uuid)

    sql_folder_ids = "SELECT id, uuid FROM folders WHERE user_id = $1 ORDER BY id DESC LIMIT 1;"
    sql_folder_ids_result = query(sql_folder_ids, user_id)
    folder_id = sql_folder_ids_result.first["id"].to_i
    folder_uuid = sql_folder_ids_result.first["uuid"]

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

    sql_relations = "INSERT INTO relations (parent_id) VALUES ($1)"
    query(sql_relations, folder_id)

    folder_uuid.delete('-')
  end

  def create_related_folder(name, tags, attr1, value1, attr2, value2, attr3, value3, user_id, uuid, parent_id)
    sql_new_folder = "INSERT INTO folders (name, tags, user_id, uuid) VALUES ($1, $2, $3, $4);"
    query(sql_new_folder, name, tags, user_id, uuid)

    sql_folder_ids = "SELECT id, uuid FROM folders WHERE user_id = $1 ORDER BY id DESC LIMIT 1;"
    sql_folder_ids_result = query(sql_folder_ids, user_id)
    folder_id = sql_folder_ids_result.first["id"].to_i
    folder_uuid = sql_folder_ids_result.first["uuid"]

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

    sql_relations = "INSERT INTO relations (parent_id, child_id) VALUES ($1, $2)"
    query(sql_relations, parent_id, folder_id)

    folder_uuid.delete('-')
  end

  def update_folder(user_id, folder_id, folder_name, folder_tags, attr1, value1, attr2, value2, attr3, value3)
    sql_folder = "UPDATE folders SET (name, tags) = ($1, $2) WHERE id = $3 AND user_id = $4;"
    query(sql_folder, folder_name, folder_tags, folder_id, user_id)

    sql_attr1 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 1 AND folder_id = $3;"
    query(sql_attr1, attr1, value1, folder_id)

    sql_attr2 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 2 AND folder_id = $3;"
    query(sql_attr2, attr2, value2, folder_id)

    sql_attr3 = "UPDATE attributes SET (name, value) = ($1, $2) WHERE position = 3 AND folder_id = $3;"
    query(sql_attr3, attr3, value3, folder_id)
  end

  def delete_folder(user_id, folder_id)
    sql = "DELETE FROM folders WHERE user_id = $1 AND id = $2;"
    query(sql, user_id, folder_id)
  end

  def note_id_by_uuid(uuid)
    sql = "SELECT id FROM notes WHERE uuid = $1;"
    query(sql, uuid).first["id"]
  end

  def load_notes(user_id, folder_id)
    sql = <<~SQL
      SELECT id AS note_id, uuid AS note_uuid, folder_uuid AS folder_uuid, title AS note_title,
        url AS note_url, url_preview AS note_url_preview, body AS note_body,
        dt AS note_date_time
      FROM notes
      WHERE user_id = $1 AND folder_id = $2
      ORDER BY dt ASC;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        note_id: tuple["note_id"],
        note_uuid: tuple["note_uuid"].delete('-'),
        folder_uuid: tuple["folder_uuid"].delete('-'),
        note_title: tuple["note_title"],
        note_url: tuple["note_url"],
        note_url_preview: tuple["note_url_preview"],
        note_body: tuple["note_body"],
        note_date_time: tuple["note_date_time"]
      }
    end
  end

  def create_note(title, url, url_preview, body, user_id, folder_id, folder_uuid, note_uuid)
    sql = <<~SQL
      INSERT INTO notes (title, url, url_preview, body, user_id, folder_id, folder_uuid, uuid)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
    SQL

    query(sql, title, url, url_preview, body, user_id, folder_id, folder_uuid, note_uuid)
  end

  def update_note(user_id, folder_id, note_id, note_title, note_url, note_url_preview, note_body)
    sql = <<~SQL
      UPDATE notes SET (title, url, url_preview, body) = ($1, $2, $3, $4) WHERE id = $5 AND folder_id = $6 AND user_id = $7;
    SQL
    query(sql, note_title, note_url, note_url_preview, note_body, note_id, folder_id, user_id)
  end

  def delete_note(user_id, folder_id, note_id)
    sql = "DELETE FROM notes WHERE user_id = $1 AND folder_id = $2 AND id = $3;"
    query(sql, user_id, folder_id, note_id)
  end

  def load_all_related_notes(user_id, folder_id)
    sql = <<~SQL
      SELECT notes.id AS note_id, notes.uuid AS note_uuid,
        folders.id AS folder_id, folders.uuid AS folder_uuid,
        folders.name AS folder_name, folders.tags AS folder_tags,
        notes.title AS note_title, notes.body AS note_body,
        notes.url AS note_url, notes.url_preview AS note_url_preview,
        notes.dt AS note_date_time
      FROM notes
      INNER JOIN folders ON notes.folder_id = folders.id
      WHERE folder_id = ANY (
        SELECT folders.id AS parent_folder
        FROM relations
        INNER JOIN folders ON relations.parent_id = folders.id
        WHERE folders.user_id = $1 AND relations.child_id = $2
      ) OR folder_id = ANY (
        SELECT relations.child_id AS child_folders
        FROM folders
        INNER JOIN relations ON relations.parent_id = folders.id
        WHERE folders.user_id = $1 and folders.id = $2
      ) OR folder_id = $2
      ORDER BY notes.dt ASC;
    SQL

    result = query(sql, user_id, folder_id)
    result.map do |tuple|
      {
        note_id: tuple["note_id"],
        note_uuid: tuple["note_uuid"].delete('-'),
        folder_id: tuple["folder_id"],
        folder_uuid: tuple["folder_uuid"].delete('-'),
        folder_name: tuple["folder_name"],
        folder_tags: tuple["folder_tags"],
        note_title: tuple["note_title"],
        note_url: tuple["note_url"],
        note_url_preview: tuple["note_url_preview"],
        note_body: tuple["note_body"],
        note_date_time: tuple["note_date_time"]
      }
    end
  end

  private

  def query(statement, *params)
    logger.info "#{statement}: #{params}"
    db.exec_params(statement, params)
  end
end
