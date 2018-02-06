# database_persistence.rb

require "pg"

class DatabasePersistence
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
end
