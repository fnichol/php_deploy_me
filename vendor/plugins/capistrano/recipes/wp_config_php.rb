Capistrano::Lastmile.load_named(:wp_config_php) do

  # =========================================================================
  # These are helper methods that will be available to your recipes.
  # =========================================================================

  ##
  # Finds the appropriate wp-config.php.erb.
  #
  def find_config_php_file
    File.join(File.dirname(__FILE__), %w{.. templates wp-config.php.erb})
  end

  ##
  # Writes out a wp-config.php from an ERB template.
  #
  def config_php
    template = File.read(File.expand_path(find_config_php_file))
    ERB.new(template).result(binding)
  end

  ##
  # Remotely connects to host and extracts database password from wp-config.php.
  #
  # @param [Symbol] var  capistrano variable that password will be assigned to
  def find_database_passwords(var= :db_password)
    if cmd_if "-f #{shared_path}/config/wp-config.php"
      php_text = capture("cat #{shared_path}/config/wp-config.php")
      set var.to_s, php_text.grep(/^define\('DB_PASSWORD', '(.*)'\);(\r)?$/){$1}.first
    end
  end

  ##
  # Sets a password variable via password prompt.
  #
  # @param [Symbol] var  capistrano variable that will be assigned to
  # @param [String] prompt  message to be displayed then asking for db password
  def prompt_db_password(var= :db_password, prompt="DB password for #{db_username}@#{db_database}: ")
    set(var.to_s) { pass_prompt(prompt) } unless exists?(var.to_s)
  end

  ##
  # Generates the secret keys randomly.
  #
  # @param [Symbol] var  capistrano variable that will be assigned to
  def generate_security_keys(var= :security_keys)
    unless exists?(var.to_s)
      set(var.to_s) do
        %x{curl https://api.wordpress.org/secret-key/1.1/salt/}
      end
    end
  end


  # =========================================================================
  # These are default variables that will be set unless overriden.
  # =========================================================================

  lm_cset(:db_username) do
    abort <<-ABORT.gsub(/^ {8}/, '')
      Please specify the name of your dabatase application user. You need
      this to be less than 16 characters for MySQL. For exaple:

        set :db_username, 'bunny_prd'

    ABORT
  end

  lm_cset :db_adapter,  "mysql"
  lm_cset :db_host,     "localhost"
  lm_cset(:db_database) { "#{application}_#{deploy_env}" }


  # =========================================================================
  # These are the tasks that are available to help with deploying web apps,
  # and specifically, wordpress applications. You can have cap give you a
  # summary of them with `cap -T'.
  # =========================================================================

  namespace :db do

    desc <<-DESC
      Prepares wp-config.php from template. If the file exists remotely, the \
      file is not created but is skipped over. To force the creation of a new \
      wp-config.php file, you can pass in the `force'' environment variable \
      like so:
      
        $ cap db:configure force=true
    DESC
    task :configure, :roles => :app, :except => { :no_release => true } do
      if cmd_if("-f #{shared_path}/config/wp-config.php") && ENV["force"].nil?
        inform "wp-config.php already exists, skipping"
      else
        ask_for_passwords
        generate_security_keys
        run "mkdir -p #{shared_path}/config"
        put config_php, "#{shared_path}/config/wp-config.php"
      end
    end

    desc <<-DESC
      [internal] Copies wp-config.php from shared_path into release_path.
    DESC
    task :cp_config_php, :roles => :app, :except => { :no_release => true } do
     run "cp #{shared_path}/config/wp-config.php #{release_path}/public/wp-config.php"
    end

    desc <<-DESC
      [internal]
      Sets variables for database passwords. This task extracts database \
      passwords from the remote wp-config.php. You can add a "before" or \
      "after" hook on this task to set other password variables if your \
      deployment has multiple database connections. For example:
      
        after "db:resolve_passwords", "my:resolve_other_passwords"
    DESC
    task :resolve_passwords, :roles => :app, :except => { :no_release => true } do
      find_database_passwords(:db_password)
    end
    
    desc <<-DESC
      [internal]
      Asks for a database password and sets a variable. This will be used to \
      inject the value into the wp-config.php template. If multiple datbase \
      connections are used, then you can add a "before" or "after" hook on \
      this task. For example:
      
        after "db:ask_for_passwords", "my:ask_for_passwords"
    DESC
    task :ask_for_passwords, :except => { :no_release => true } do
      prompt_db_password(:db_password)
    end
  end

  after "deploy:setup", "db:configure"
  after "deploy:update_code", "db:cp_config_php"
end
