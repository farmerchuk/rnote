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

# ---------------------------------------
# ROUTES
# ---------------------------------------

get "/" do
  redirect "/folders/new"
end

get "/folders/new" do
  @parent_id = params[:parent_id]
  @parent_name = params[:parent_name]

  erb :new_folder, layout: :layout
end

post "/folders/new" do
  if pass_form_validations?
    new_folder_params = [
      params['name'], params['type'], params['attr1'], params['value1'],
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
  @folder_type = folder.first[:folder_type]

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

  erb :folder, layout: :layout
end

get "/folders/:id/edit" do
  @folder_id = params[:id].to_i
  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_type = folder.first[:folder_type]

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
    folder_type = params[:type]
    folder_attr1 = params[:attr1]
    folder_value1 = params[:value1]
    folder_attr2 = params[:attr2]
    folder_value2 = params[:value2]
    folder_attr3 = params[:attr3]
    folder_value3 =  params[:value3]

    @storage.update_folder(@user_id, folder_id, folder_name, folder_type,
                           folder_attr1, folder_value1,
                           folder_attr2, folder_value2,
                           folder_attr3, folder_value3)

    redirect "/folders/#{folder_id}"
  else
    erb :edit_folder, layout: :layout
  end
end

get "/folders/:id/notes/new" do
  @folder_id = params[:id].to_i
  folder = @storage.load_folder(@user_id, @folder_id)

  @folder_name = folder.first[:folder_name]
  @folder_type = folder.first[:folder_type]

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

  erb :new_note, layout: :layout
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
  @folder_type = folder.first[:folder_type]

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

  erb :edit_note, layout: :layout
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
  @folder_type = folder.first[:folder_type]

  @folder_attributes = []
  folder.each_with_index do |row, idx|
    @folder_attributes << {
      name: folder[idx][:attr_name],
      value: folder[idx][:attr_value]
    }
  end

  @related_folders = @storage.load_related_child_folders(@user_id, @folder_id)

  @notes = @storage.load_all_related_notes(@user_id, @folder_id).reverse

  erb :all_related_notes, layout: :layout
end
