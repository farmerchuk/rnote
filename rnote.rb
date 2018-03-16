require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "uuid"
require "bcrypt"
require "pry"
require "metainspector"

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
  @user_id = get_user_id_from_uuid(session[:user_uuid])
  @user_name = session[:user_name]
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
    date.split('.').first.split(' ').join(' at ')
  end
end

# ---------------------------------------
# ROUTE HELPERS
# ---------------------------------------

def generate_uuid
  UUID.new.generate
end

def user_logged_in?
  !!@user_id
end

def redirect_if_not_logged_in
  unless user_logged_in?
    redirect "/"
  end
end

def password_correct?(password, password_on_file)
  password_on_file = BCrypt::Password.new(password_on_file)
  password_on_file == password
end

def get_user_id_from_uuid(uuid)
  uuid ? @storage.user_id_by_uuid(uuid).to_i : nil
end

def get_folder_id_from_uuid(uuid)
  uuid ? @storage.folder_id_by_uuid(uuid).to_i : nil
end

def get_note_id_from_uuid(uuid)
  uuid ? @storage.note_id_by_uuid(uuid).to_i : nil
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
# VALIDATIONS
# ---------------------------------------

def pass_form_validations?
  true
end

def pass_name_validation(name)
  errors = {
    name: []
  }

  if name.size < 3
    errors[:name] << 'Name must be at least 3 characters long.'
  end

  errors.any? { |_, error_list| !error_list.empty? } ? errors : nil
end

def pass_user_validations(email, password)
  errors = {
    email: [],
    password: []
  }

  if !email.match(/\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i)
    errors[:email] << 'Please enter a valid email address.'
  end

  if !password.match(/^(?=.*[a-zA-Z])(?=.*[0-9]).{8,}$/)
    errors[:password] << 'Password must be at least 8 characters long and include both letters and numbers.'
  end

  errors.any? { |_, error_list| !error_list.empty? } ? errors : nil
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

# ---------------------------------------
# ROUTES
# ---------------------------------------

get "/" do
  if user_logged_in?
    redirect "/folders/find_folder"
  else
    redirect "/sign_in"
  end
end

get "/sign_in" do
  erb :login
end

post "/sign_in" do
  email = params[:email]
  password = params[:password]
  @errors = pass_user_validations(email, password)

  if !@errors
    user = @storage.get_user_by_email(email)

    if user
      password_on_file = user[:password]
      if password_correct?(password, password_on_file)
        session[:user_uuid] = user[:uuid]
        session[:user_name] = user[:name]
        redirect "/folders/find_folder"
      else
        erb :login
      end
    else
      session[:user_email] = email
      session[:user_password] = password

      redirect "/new_user"
    end
  else
    erb :login
  end
end

get "/new_user" do
  @new_user = true
  erb :login
end

post "/create_account" do
  name = params[:name]
  @name_errors = pass_name_validation(name)

  if !@name_errors
    email = session[:user_email]
    password = session[:user_password]

    user_errors = pass_user_validations(email, password)

    session[:user_email] = nil
    session[:user_password] = nil

    if !user_errors
      encrypted_password = BCrypt::Password.create(password)
      uuid = generate_uuid

      new_user = @storage.create_user(name, uuid, email, encrypted_password)

      session[:user_uuid] = new_user[:uuid]
      session[:user_name] = new_user[:name]

      redirect "/folders/new"
    else
      redirect "/sign_in"
    end
  else
    @new_user = true
    erb :login
  end
end

get "/logout" do
  session[:user_uuid] = nil
  session[:user_name] = nil
  redirect "/"
end

get "/folders/find_folder" do
  redirect_if_not_logged_in

  @query = params[:query] || ""
  type_filter = params[:filter_by_tag] || ""
  sort_method = params[:sort] || "alphabetical"
  @folders = @storage.load_folders(@user_id, @query, type_filter, sort_method)
  @folder_tags = parse_folder_tags(@folders)

  erb :find_folder, layout: :layout_flexible
end

get "/folders/new" do
  redirect_if_not_logged_in

  @parent_uuid = params[:parent_uuid]
  @parent_name = params[:parent_name]

  erb :new_folder, layout: :layout_flexible
end

post "/folders/new" do
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

  folder_id = get_folder_id_from_uuid(params[:uuid])
  @storage.delete_folder(@user_id, folder_id)

  redirect "/folders/find_folder"
end

get "/folders/:from_folder_uuid/link" do
  redirect_if_not_logged_in

  @page_type = :link_folder
  @from_folder_uuid = params[:from_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(@from_folder_uuid)
  from_folder = @storage.load_folder(@user_id, @from_folder_id)
  @from_folder_name = from_folder.first[:folder_name]
  @from_folder_tags_string = from_folder.first[:folder_tags]

  @query = params[:query] || ""
  type_filter = params[:filter_by_tag] || ""
  sort_method = params[:sort] || "alphabetical"
  @folders = @storage.load_linkable_folders(@user_id, @query, @from_folder_id, type_filter, sort_method)
  @folder_tags = parse_folder_tags(@folders)

  erb :link_folder, layout: :layout_flexible
end

post "/folders/:from_folder_uuid/link/:to_folder_uuid" do
  redirect_if_not_logged_in

  from_folder_uuid = params[:from_folder_uuid]
  to_folder_uuid = params[:to_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(from_folder_uuid)
  @to_folder_id = get_folder_id_from_uuid(to_folder_uuid)

  @storage.link_folders(@from_folder_id, @to_folder_id)

  redirect "/folders/#{from_folder_uuid}"
end

get "/folders/:from_folder_uuid/unlink" do
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

  from_folder_uuid = params[:from_folder_uuid]
  to_folder_uuid = params[:to_folder_uuid]
  @from_folder_id = get_folder_id_from_uuid(from_folder_uuid)
  @to_folder_id = get_folder_id_from_uuid(to_folder_uuid)

  @storage.unlink_folders(@from_folder_id, @to_folder_id)

  redirect "/folders/#{from_folder_uuid}"
end

get "/folders/:uuid/notes/new" do
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

  if pass_form_validations?
    folder_uuid = params[:uuid]
    folder_id = get_folder_id_from_uuid(folder_uuid)
    title = params[:title]
    body = params[:body]
    note_uuid = generate_uuid

    @storage.create_note(title, "", "", body, @user_id, folder_id, folder_uuid, note_uuid)

    redirect "/folders/#{folder_uuid}"
  else
    erb :new_note, layout: :layout_standard
  end
end

get "/folders/:uuid/notes_url/new" do
  redirect_if_not_logged_in

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

  erb :new_note_url, layout: :layout_standard
end

post "/folders/:uuid/notes_url/new" do
  redirect_if_not_logged_in

  if pass_form_validations?
    folder_uuid = params[:uuid]
    folder_id = get_folder_id_from_uuid(folder_uuid)
    title = params[:title]
    url = params[:url]
    body = params[:body]
    note_uuid = generate_uuid

    page = MetaInspector.new(url)
    url_preview = page.images.best

    @storage.create_note(title, url, url_preview, body, @user_id, folder_id, folder_uuid, note_uuid)

    redirect "/folders/#{folder_uuid}"
  else
    erb :new_note, layout: :layout_standard
  end
end

get "/folders/:folder_uuid/notes/:note_uuid/edit" do
  redirect_if_not_logged_in

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
  redirect_if_not_logged_in

  if params[:action] == "Update Note"
    if pass_form_validations?
      folder_uuid = params[:folder_uuid]
      folder_id = get_folder_id_from_uuid(folder_uuid)
      note_id = get_note_id_from_uuid(params[:note_uuid])
      note_title = params[:title]
      note_body = params[:body]

      @storage.update_note(@user_id, folder_id, note_id, note_title, "", "", note_body)

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

get "/folders/:folder_uuid/notes_url/:note_uuid/edit" do
  redirect_if_not_logged_in

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

  erb :edit_note_url, layout: :layout_standard
end

post "/folders/:folder_uuid/notes_url/:note_uuid/edit" do
  redirect_if_not_logged_in

  if params[:action] == "Update Link"
    if pass_form_validations?
      folder_uuid = params[:folder_uuid]
      folder_id = get_folder_id_from_uuid(folder_uuid)
      note_id = get_note_id_from_uuid(params[:note_uuid])
      note_title = params[:title]
      note_url = params[:url]
      note_body = params[:body]

      page = MetaInspector.new(note_url)
      note_url_preview = page.images.best

      @storage.update_note(@user_id, folder_id, note_id, note_title, note_url, note_url_preview, note_body)

      redirect "/folders/#{folder_uuid}"
    else
      erb :edit_folder, layout: :layout_flexible
    end
  elsif params[:action] == "Delete Link"
    folder_uuid = params[:folder_uuid]
    folder_id = get_folder_id_from_uuid(folder_uuid)
    note_id = get_note_id_from_uuid(params[:note_uuid])

    @storage.delete_note(@user_id, folder_id, note_id)

    redirect "/folders/#{folder_uuid}"
  end
end

get "/folders/:folder_uuid/all_related_notes" do
  redirect_if_not_logged_in

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
