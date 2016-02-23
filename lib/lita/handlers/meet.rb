require 'json'
module Lita
  module Handlers
    class Meet < Handler
      config :name_of_auth_group, type: Symbol, default: :standup_participants, required: true
      config :time_to_respond, types: [Integer, Float], default: 60 #minutes
      config :api_key, type: String, default: 'qArnqfhXFb3DWMYtOXuKxjG3iLGHYXHxKnZurDbFAQx2T0zsnm8DrQSYBQep6Njo'
      config :enable_http
      config :standup_message, type: String, default: "Please tell me what you did yesterday, 1. what you're doing now 2. what you're working on today 3. something fun. Please prepend your answer with 'standup response'", required: true


      # handler bot routes
      route(/start standup$/, :start_standup, command: true, help: {"start standup" => "triggers a standup"})
      route(/standup response (1.*)(2.*)(3.*)/, :store_response, command: true, help: {"standup response" => "record list of 1. 2. 3. items and replay in room"})
      route(/^standup play$/, :update_room, command: true, help: {"standup play" => "plays all the responses recieved" })
      route(/^standup playback (\d{4})(\d{2})(\d{2})$/, :playback, command: true, help: {"standup playback date" => "plays back a standup from a given date. Date must be in yyyymmdd format"})

      # Http routes
      http.get "/startstandup/:key", :trigger_standup
      http.get "/standups/:key/:date", :fetch_standup

      # START http route commands
      def fetch_standup(request, response)
        if config.enable_http == 'on'
          if request.env["router.params"][:key] == config.api_key
            json_output = {}
            response_prefix = request.env["router.params"][:date]
            json_output["standup-date"] = response_prefix
            redis.keys.each do |key|
              if key.to_s.include? response_prefix
                user = key.gsub(Date.parse(response_prefix).strftime('%Y%m%d') + '-', "")
                json_output[user] = JSON.parse(redis.get(key))
              end
            end
            response.headers["Content-Type"] = "application/json"
            response.write(MultiJson.dump(json_output))
          else
            response.write("invalid api key!")
          end
        else
            response.write("Http isn't enabled. Please enable it in the config by put in lita_config.rb, config.handlers.meet.enable_http = true")
        end
      end

      def trigger_standup(request, response)
        if config.enable_http == 'on'
          if request.env["router.params"][:key] == config.api_key
            redis.set('last_standup_started_at', Time.now)
            find_and_create_users
            message_all_users
          else
            response.write("invalid api key!")
          end
        else
          response.write("Http isn't enabled. Please enable it in the config by put in lita_config.rb, config.handlers.meet.enable_http = true")
        end
      end
      # END http route commands

      # START bot methods
      def start_standup(response)
        redis.set('last_standup_started_at', Time.now)
        find_and_create_users
        message_all_users
        last_check = redis.get('started_at')
        until whole_team do
           if last_check > 15.minutes.ago
              results = check_completion
              if results['not_completed'].count > 0
                results['not_completed'].each do |user|
                  send_nag(user)
                end
              end
            else
              last_check = True
              update_room
            end
        end
      end

      def store_response(response)
        #TODO: add check for the last person to response, trigger a play in the room
        return unless timing_is_right?
        response.reply('Response recorded. Thanks for partipating')
        date_string = Time.now.strftime('%Y%m%d')
        user_name = response.user.name.split(' ').join('_') #lol
        redis.set(date_string + '-' + user_name, response.matches.first)
      end

      def update_room(response)
        room = Source.new(room: response.room)
        message_body = ''
        response_prefix = Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d')
        redis.keys.each do |key|
          if key.to_s.include? response_prefix
            message_body += key.gsub(Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d') + '-', "")
            message_body += "\n"
            message_body += MultiJson.load(redis.get(key)).join("\n")
            message_body += "\n"
          end
        end
        robot.send_message(room, message_body)
      end

      def playback(response)
        message_body = ''
        playback_param = response.matches.first
        search_date = playback_param[0]+playback_param[1]+playback_param[2]
        message_body += "Playing back standup from #{search_date}: \n\n"
        redis.keys.each do |key|
          if key.to_s.include? search_date
            message_body += key.gsub(Date.parse(search_date).strftime('%Y%m%d') + '-', "")
            message_body += "\n"
            message_body += MultiJson.load(redis.get(key)).join("\n")
            message_body += "\n"
          end
        end
        response.reply_privately(message_body)
      end

      # END bot methods

      private

      def check_completion
        completed = []
        not_completed = []
        results = []
        check_prefix = Date.parse(redis.get("last_standup_started_at")).strftime('%Y%m%d')
        @users.each do | user |
          check = redis.get(check_prefix + "-" + user)
          if check.nil?
            not_completed[] = user
          else
            completed[] = user
          end
        end
        results['completed'] = completed
        results['not_completed'] = not_completed
        return results
      end

      def send_nag(user)
        source = Lita::Source.new(user: user)
        robot.send_message(source, 'Hate to nag like a wife but would for the shake of god.')
        robot.send_message(source, 'Send in your Standup notes using standup response!')
      end

      def message_all_users
        @users.each do |user|
          source = Lita::Source.new(user: user)
          robot.send_message(source, "Time for standup!")
          robot.send_message(source, config.standup_message)
        end
      end

      def find_and_create_users
        @users ||= robot.auth.groups_with_users[config.name_of_auth_group]
      end

      def timing_is_right?
        return false if redis.get('last_standup_started_at').nil?
        intitiated_at = Time.parse(redis.get('last_standup_started_at'))
        Time.now > intitiated_at && intitiated_at + (60*config.time_to_respond) > Time.now
      end

      Lita.register_handler(self)
    end
  end
end
