require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
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

def parse_folder_tags(raw_folder_tags)
  raw_folder_tags.map { |tags| tags.split(' ') }.flatten.uniq.sort
end

def format_folder_tags_as_string(folder_tags)
  folder_tags.split(' ').map { |tags| "##{tags}"}.sort.join(' ')
end

def format_folder_tags_as_array(folder_tags)
  folder_tags.split(' ').map { |tags| "##{tags}"}.sort
end

def filter_sort_folders(folders, filter_by_tag, sort)
  if filter_by_tag != "all_tags" && filter_by_tag != nil
    folders = folders.select { |folder| folder[:folder_tags].include?(filter_by_tag) }
  end
  if sort == "recently_created_first" || sort == "recently_created_last"
    folders = folders.sort_by { |folder| folder[:date_time] }
    folders.reverse! if sort == "recently_created_first"
  end

  folders
end

# ---------------------------------------
# ROUTES
# ---------------------------------------

get "/" do
  redirect "/folders/new"
end

get "/folders/find_folder" do
  @query = params[:query] || ""
  @all_folders = @storage.find_folders(@user_id, @query)
  @raw_folder_tags = @storage.list_folder_tags(@user_id)
  @folder_tags = parse_folder_tags(@raw_folder_tags)
  @folders = filter_sort_folders(@all_folders, params[:filter_by_tag], params[:sort])

  erb :find_folder, layout: :layout
end

get "/folders/new" do
  @parent_id = params[:parent_id]
  @parent_name = params[:parent_name]

  erb :new_folder, layout: :layout
end

post "/folders/new" do
  if pass_form_validations?
    new_folder_params = [
      params['name'], params['tags'].downcase, params['attr1'], params['value1'],
      params['attr2'], params['value2'], params['attr3'], params['value3'], @user_id
    ]

    if params[:parent_id]
      new_folder_params << params['parent_id'].to_i
      folder_id = @storage.create_related_folder(*new_folder_params)
    else
      folder_id = @storage.create_folder(*new_folder_params)
    end

    redirect "/folders/#{folder_id}"
  else
    erb :new_folder, layout: :layout
  end
end

get "/folders/:id" do
  @folder_id = params[:id].to_i
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

  @related_folders = @storage.load_related_child_folders(@user_id, @folder_id)
  @parent_folder = @storage.load_parent_folder(@user_id, @folder_id)

  erb :folder, layout: :layout_standard
end

get "/folders/:id/edit" do
  @folder_id = params[:id].to_i
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

  erb :edit_folder, layout: :layout
end

post "/folders/:id/edit" do
  if pass_form_validations?
    folder_id = params[:id]
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

    redirect "/folders/#{folder_id}"
  else
    erb :edit_folder, layout: :layout
  end
end

post "/folders/:id/delete" do
  folder_id = params[:id]
  @storage.delete_folder(@user_id, folder_id)

  redirect "/"
end

get "/folders/:id/notes/new" do
  @folder_id = params[:id].to_i
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

  @related_folders = @storage.load_related_child_folders(@user_id, @folder_id)
  @parent_folder = @storage.load_parent_folder(@user_id, @folder_id)

  erb :new_note, layout: :layout_standard
end

post "/folders/:id/notes/new" do
  if pass_form_validations?
    folder_id = params[:id]
    title = params[:title]
    body = params[:body]

    @storage.create_note(title, body, @user_id, folder_id)

    redirect "/folders/#{folder_id}"
  else
    erb :new_note, layout: :layout
  end
end

get "/folders/:folder_id/notes/:note_id/edit" do
  @folder_id = params[:folder_id].to_i
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
  @note_id = params[:note_id].to_i

  @related_folders = @storage.load_related_child_folders(@user_id, @folder_id)
  @parent_folder = @storage.load_parent_folder(@user_id, @folder_id)

  erb :edit_note, layout: :layout_standard
end

post "/folders/:folder_id/notes/:note_id/edit" do
  if pass_form_validations?
    folder_id = params[:folder_id]
    note_id = params[:note_id]
    note_title = params[:title]
    note_body = params[:body]

    @storage.update_note(@user_id, folder_id, note_id, note_title, note_body)

    redirect "/folders/#{folder_id}"
  else
    erb :edit_folder, layout: :layout
  end
end

get "/folders/:folder_id/all_related_notes" do
  @folder_id = params[:folder_id].to_i
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

  @related_folders = @storage.load_related_child_folders(@user_id, @folder_id)

  @notes = @storage.load_all_related_notes(@user_id, @folder_id).reverse

  erb :all_related_notes, layout: :layout_standard
end
