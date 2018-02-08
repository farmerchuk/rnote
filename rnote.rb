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
  erb :folder, layout: :layout
end

get "/folders/new" do
  erb :new_folder, layout: :layout
end

post "/folders/new" do
  if pass_form_validations?
    folder_params = params.values << @user_id
    folder_id = @storage.create_folder(*folder_params)

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

  erb :folder, layout: :layout
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

  erb :new_note, layout: :layout
end

post "/folders/:id/notes/new" do
  if pass_form_validations?
    folder_id = params[:id]
    note_params = params.values << @user_id
    @storage.create_note(*folder_params)

    redirect "/folders/#{folder_id}"
  else
    erb :new_note, layout: :layout
  end
end
