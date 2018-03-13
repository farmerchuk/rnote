require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "uuid"
require "pry"

require_relative "lib/database"

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, "secret"
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database.rb"
end

before do
  @storage = Database.new(logger)
  @user_id = 1
end

after do
  @storage.disconnect
end

# ---------------------------------------
# VIEW HELPERS
# ---------------------------------------

helpers do
  def new_line_to_br(string)
    string.gsub(/[\r]/, "<br />")
  end

  def format_date(date)
    date.split('.').first
  end
end

# ---------------------------------------
# ROUTE HELPERS
# ---------------------------------------

def pass_form_validations?
  true
end

def generate_uuid
  UUID.new.generate
end

def get_folder_id_from_uuid(uuid)
  uuid ? @storage.folder_id_by_uuid(uuid).to_i : nil
end

def get_note_id_from_uuid(uuid)
  uuid ? @storage.note_id_by_uuid(uuid).to_i : nil
end

def new_folder_validations(params)
  errors = {
    folder_name: [], folder_tags: [], folder_attr1: [],
    folder_attr2: [], folder_attr3: []
  }

  if folder_name_exists?(params['name'])
    errors[:folder_name] << 'Folder name already exists.'
  end

  if params['name'].length < 3
    errors[:folder_name] << 'Folder name must be at least 3 characters.'
  end

  if params['name'].length == 0
    errors[:folder_name] << 'Folder name cannot be blank.'
  end

  if params['tags'].length == 0
    errors[:folder_tags] << 'Enter at least one tag.'
  end

  if !params['tags'].match(/^[a-z0-9 _-]+$/i)
    errors[:folder_tags] << 'Alpha-numeric characters, spaces, underscores and hyphens only.'
  end

  errors.any? { |_, error_list| !error_list.empty? } ? errors : nil
end

def edit_folder_validations(params, folder_id)
  errors = {
    folder_name: [], folder_tags: [], folder_attr1: [],
    folder_attr2: [], folder_attr3: []
  }
  new_folder_name = params['name']
  current_folder_name = @storage.folder_name_by_id(folder_id)

  if folder_name_exists?(new_folder_name) && new_folder_name != current_folder_name
    errors[:folder_name] << 'Folder name already exists.'
  end

  if params['name'].length < 3
    errors[:folder_name] << 'Folder name must be at least 3 characters.'
  end

  if params['name'].length == 0
    errors[:folder_name] << 'Folder name cannot be blank.'
  end

  if params['tags'].length == 0
    errors[:folder_tags] << 'Enter at least one tag.'
  end

  if !params['tags'].match(/^[a-z0-9 _-]+$/i)
    errors[:folder_tags] << 'Alpha-numeric characters, spaces, underscores and hyphens only.'
  end

  errors.any? { |_, error_list| !error_list.empty? } ? errors : nil
end

def folder_name_exists?(new_folder_name)
  existing_folder_names = @storage.load_folder_names_by_user(@user_id)
  existing_folder_names.any? { |folder_name| folder_name == new_folder_name.downcase}
end

def parse_folder_tags(folders)
  folders.map do |folder|
    folder[:folder_tags].split(' ')
  end.flatten.uniq.sort
end

def format_folder_tags_as_string(folder_tags)
  folder_tags.split(' ').map { |tags| "##{tags}"}.sort.join(' ')
end

def format_folder_tags_as_array(folder_tags)
  folder_tags.split(' ').map { |tags| "##{tags}"}.sort
end

def sort_folders_alphabetically(folders)
  folders.sort_by { |folder| folder[:folder_name] }
end

# ---------------------------------------
# ROUTES
# ---------------------------------------

get "/" do
  redirect "/folders/find_folder"
end

get "/folders/find_folder" do
  @query = params[:query] || ""
  type_filter = params[:filter_by_tag] || ""
  sort_method = params[:sort] || "alphabetical"
  @folders = @storage.load_folders(@user_id, @query, type_filter, sort_method)
  @folder_tags = parse_folder_tags(@folders)

  erb :find_folder, layout: :layout_flexible
end

get "/folders/new" do
  @parent_uuid = params[:parent_uuid]
  @parent_name = params[:parent_name]

  erb :new_folder, layout: :layout_flexible
end

post "/folders/new" do
  @errors = new_folder_validations(params)

  if !@errors
    uuid = generate_uuid
    new_folder_params = [
      params['name'], params['tags'].downcase, params['attr1'], params['value1'],
      params['attr2'], params['value2'], params['attr3'], params['value3'], @user_id, uuid
    ]

    if params[:parent_uuid]
      parent_id = get_folder_id_from_uuid(params[:parent_uuid])
      new_folder_params << parent_id
      folder_uuid = @storage.create_related_folder(*new_folder_params)
    else
      folder_uuid = @storage.create_folder(*new_folder_params)
    end

    redirect "/folders/#{folder_uuid}"
  else
    erb :new_folder, layout: :layout_flexible
  end
end

get "/folders/:uuid" do
  @folder_id = get_folder_id_from_uuid(params[:uuid])
  @folder_uuid = params[:uuid]

  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_tags = folder.first[:folder_tags].split(' ')

  @folder_attributes = []

  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  @notes = @storage.load_notes(@user_id, @folder_id).reverse
  @selected_folders = @storage.load_related_folders(@user_id, @folder_id)
  @related_folders = sort_folders_alphabetically(@selected_folders)

  erb :folder, layout: :layout_standard
end

get "/folders/:uuid/edit" do
  @folder_id = get_folder_id_from_uuid(params[:uuid])
  @folder_uuid = params[:uuid]

  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_tags_string = folder.first[:folder_tags]

  @folder_attributes = []
  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  erb :edit_folder, layout: :layout_flexible
end

post "/folders/:uuid/edit" do
  @folder_uuid = params[:uuid]
  folder_id = get_folder_id_from_uuid(@folder_uuid)

  @errors = edit_folder_validations(params, folder_id)

  if !@errors
    folder_name = params[:name]
    folder_tags = params[:tags].downcase
    folder_attr1 = params[:attr1]
    folder_value1 = params[:value1]
    folder_attr2 = params[:attr2]
    folder_value2 = params[:value2]
    folder_attr3 = params[:attr3]
    folder_value3 =  params[:value3]

    @storage.update_folder(@user_id, folder_id, folder_name, folder_tags,
                           folder_attr1, folder_value1,
                           folder_attr2, folder_value2,
                           folder_attr3, folder_value3)

    redirect "/folders/#{@folder_uuid}"
  else
    erb :edit_folder, layout: :layout_flexible
  end
end

post "/folders/:uuid/delete" do
  folder_id = get_folder_id_from_uuid(params[:uuid])
  @storage.delete_folder(@user_id, folder_id)

  redirect "/folders/find_folder"
end

get "/folders/:from_folder_uuid/link" do
  @page_type = :link_folder
  @from_folder_uuid = params[:from_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(@from_folder_uuid)
  from_folder = @storage.load_folder(@user_id, @from_folder_id)
  @from_folder_name = from_folder.first[:folder_name]
  @from_folder_tags_string = from_folder.first[:folder_tags]

  @query = params[:query] || ""
  type_filter = params[:filter_by_tag] || ""
  sort_method = params[:sort] || "alphabetical"
  @folders = @storage.load_linkable_folders(@query, @from_folder_id, type_filter, sort_method)
  @folder_tags = parse_folder_tags(@folders)

  erb :link_folder, layout: :layout_flexible
end

post "/folders/:from_folder_uuid/link/:to_folder_uuid" do
  from_folder_uuid = params[:from_folder_uuid]
  to_folder_uuid = params[:to_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(from_folder_uuid)
  @to_folder_id = get_folder_id_from_uuid(to_folder_uuid)

  @storage.link_folders(@from_folder_id, @to_folder_id)

  redirect "/folders/#{from_folder_uuid}"
end

get "/folders/:from_folder_uuid/unlink" do
  @page_type = :unlink_folder
  @from_folder_uuid = params[:from_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(@from_folder_uuid)
  from_folder = @storage.load_folder(@user_id, @from_folder_id)
  @from_folder_name = from_folder.first[:folder_name]
  @from_folder_tags_string = from_folder.first[:folder_tags]

  @query = params[:query] || ""
  type_filter = params[:filter_by_tag] || ""
  sort_method = params[:sort] || "alphabetical"
  @folders = @storage.load_related_folders_with_query(@user_id, @from_folder_id, @query, type_filter, sort_method)
  @folder_tags = parse_folder_tags(@folders)

  erb :unlink_folder, layout: :layout_flexible
end

post "/folders/:from_folder_uuid/unlink/:to_folder_uuid" do
  from_folder_uuid = params[:from_folder_uuid]
  to_folder_uuid = params[:to_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(from_folder_uuid)
  @to_folder_id = get_folder_id_from_uuid(to_folder_uuid)

  @storage.unlink_folders(@from_folder_id, @to_folder_id)

  redirect "/folders/#{from_folder_uuid}"
end

get "/folders/:uuid/notes/new" do
  @folder_uuid = params[:uuid]
  @folder_id = get_folder_id_from_uuid(@folder_uuid)
  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_tags = folder.first[:folder_tags].split(' ')

  @folder_attributes = []
  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  @notes = @storage.load_notes(@user_id, @folder_id).reverse
  @selected_folders = @storage.load_related_folders(@user_id, @folder_id)
  @related_folders = sort_folders_alphabetically(@selected_folders)

  erb :new_note, layout: :layout_standard
end

post "/folders/:uuid/notes/new" do
  if pass_form_validations?
    folder_uuid = params[:uuid]
    folder_id = get_folder_id_from_uuid(folder_uuid)
    title = params[:title]
    body = params[:body]
    uuid = generate_uuid

    @storage.create_note(title, body, @user_id, folder_id, uuid)

    redirect "/folders/#{folder_uuid}"
  else
    erb :new_note, layout: :layout_standard
  end
end

get "/folders/:folder_uuid/notes/:note_uuid/edit" do
  @folder_uuid = params[:folder_uuid]
  @folder_id = get_folder_id_from_uuid(@folder_uuid)
  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_tags = folder.first[:folder_tags].split(' ')

  @folder_attributes = []
  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  @notes = @storage.load_notes(@user_id, @folder_id).reverse
  @note_uuid = params[:note_uuid]
  @note_id = get_note_id_from_uuid(@note_uuid)

  @selected_folders = @storage.load_related_folders(@user_id, @folder_id)
  @related_folders = sort_folders_alphabetically(@selected_folders)

  erb :edit_note, layout: :layout_standard
end

post "/folders/:folder_uuid/notes/:note_uuid/edit" do
  if params[:action] == "Update Note"
    if pass_form_validations?
      folder_uuid = params[:folder_uuid]
      folder_id = get_folder_id_from_uuid(folder_uuid)
      note_id = get_note_id_from_uuid(params[:note_uuid])
      note_title = params[:title]
      note_body = params[:body]

      @storage.update_note(@user_id, folder_id, note_id, note_title, note_body)

      redirect "/folders/#{folder_uuid}"
    else
      erb :edit_folder, layout: :layout_flexible
    end
  elsif params[:action] == "Delete Note"
    folder_uuid = params[:folder_uuid]
    folder_id = get_folder_id_from_uuid(folder_uuid)
    note_id = get_note_id_from_uuid(params[:note_uuid])

    @storage.delete_note(@user_id, folder_id, note_id)

    redirect "/folders/#{folder_uuid}"
  end
end

get "/folders/:folder_uuid/all_related_notes" do
  @folder_uuid = params[:folder_uuid]
  @folder_id = get_folder_id_from_uuid(@folder_uuid)
  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_tags = folder.first[:folder_tags].split(' ')

  @folder_attributes = []
  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  @selected_folders = @storage.load_related_folders(@user_id, @folder_id)
  @related_folders = sort_folders_alphabetically(@selected_folders)
  @notes = @storage.load_all_related_notes(@user_id, @folder_id).reverse

  erb :all_related_notes, layout: :layout_standard
end
