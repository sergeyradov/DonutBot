require 'sinatra/base'
require 'slack-ruby-client'
require 'pry'


# This class contains all of the webserver logic for processing incoming requests from Slack.
class API < Sinatra::Base
  # This is the endpoint Slack will post Event data to.
  post '/events' do
    request_data = JSON.parse(request.body.read)
    # Check the verification token provided with the request to make sure it matches the verification token in
    # your app's setting to confirm that the request came from Slack.
    unless SLACK_CONFIG[:slack_verification_token] == request_data['token']
      halt 403, "Invalid Slack verification token received: #{request_data['token']}"
    end

    case request_data['type']
      when 'url_verification'
        request_data['challenge']

      when 'event_callback'
        # Get the Team ID and Event data from the request object
        team_id = request_data['team_id']
        event_data = request_data['event']

        case event_data['type']
          when 'message'
            Events.send_task(team_id, event_data)
          else
            puts "Unexpected event:\n"
            puts JSON.pretty_generate(request_data)
        end
        status 200
    end
  end

  post '/actions' do
    request_payload = request.env['rack.request.form_hash']['payload']
    request_data = JSON.parse(request_payload)
    if request_data["callback_id"] == "intro"
      Actions.send_tutorial(request_data["team"]["id"], request_data["user"]["id"])
    elsif request_data["callback_id"] == "error"
      Actions.send_tutorial(request_data["team"]["id"], request_data["user"]["id"])
    elsif request_data["callback_id"] != "disabled"
      Actions.respond(request_data)
    end
    status 200
  end

  post '/tutorial' do
    request_data = request.env['rack.request.form_hash']
    Actions.send_tutorial(request_data["team_id"], request_data["user_id"])
    status 200
  end
end

# This class contains all of the Event handling logic.
class Events

  def self.parseMessage(message)
    id_spans = []
    current_span = []
    message.chars.each_with_index do |ch, i|
      return nil if i == 0 and ch != "<"
      if ch == '<'
        current_span << i
        return nil if message[i+1] != "@"
      elsif ch == '>'
        current_span << i
        id_spans << current_span
        current_span = []
      end
    end

    commands = []
    id_spans.each_with_index do |span, i|
      id = message[span[0]+1...span[1]]
      id = id[1..-1] if id[0] == "@"

      end_idx = id_spans[i+1] ? id_spans[i+1][0] : message.length
      command = message[span[1]+1...end_idx]
      command = command[1..-1] if command[0] == " "
      commands << {id: id, command: command}
    end
    return commands
  end

  def self.send_task(team_id, event_data)
    user_id = event_data['user']
    # Don't process messages sent from our bot user
    unless user_id == $teams[team_id][:bot_user_id]

      # USER SENDS DM TO BOT THAT @S A USER
      if event_data['text'] && event_data['text'][0..1] == "<@"
        commands = Events.parseMessage(event_data['text'])
        commands.each do |command|
          if command[:command] != ""
            $teams[team_id]['client'].chat_postMessage(
              as_user: 'true',
              channel: command[:id],
              text: "New Task!",
              attachments: [
                {
                  color: "#3c0783",
                  callback_id: event_data['channel'],
                  attachment_type: "default",
                  fields: [
                    {title: "Task Description", value: "#{command[:command]}"},
                    {title: "Assigned by:", value: "<@#{user_id}>"}
                  ],
                  actions: [
                    {
                      name: "option",
                      value: "completed",
                      text: ":white_large_square: Complete?",
                      type: "button"
                    }
                  ]
                }
              ]
            )
          else
            $teams[team_id]['client'].chat_postMessage(
              as_user: 'true',
              channel: user_id,
              attachments: [
                color: "#3c0783",
                callback_id: "error",
                attachment_type: "default",
                title: ":rotating_light:Error Sending Message:rotating_light:",
                text: "DonutBot could not send your task to <@#{command[:id]}>.\n\nPlease include text in task description.",
                actions: [
                  {
                    name: "tutorial_button",
                    value: "view_tutorial",
                    text: "View Tutorial",
                    type: "button"
                  }
                ]
              ]
            )
          end
        end
      else
        $teams[team_id]['client'].chat_postMessage(
          as_user: 'true',
          channel: user_id,
          attachments: [
            color: "#3c0783",
            callback_id: "intro",
            attachment_type: "default",
            title: ":doughnut:Welcome!:robot_face:",
            text: "Hello and welcome to DonutBot! Would you like to view a tutorial?",
            actions: [
              {
                name: "tutorial_button",
                value: "view_tutorial",
                text: "View Tutorial",
                type: "button"
              }
            ]
          ]
        )
        # Actions.send_tutorial(team_id, user_id)
      end
    end
  end

end

class Actions
  def self.respond(data)

    unless data["callback_id"] == "disabled"

      team_id = data["team"]["id"]

      #SEND OUT RESPONSE MESSAGE
      $teams[team_id]['client'].chat_postMessage(
        as_user: 'true',
        channel: data["callback_id"],
        attachments: [
          {
            color: "#3c0783",
            title: "Task Completed!",
            text: "<@#{data["user"]["id"]}> has completed your task:\n'#{data["original_message"]["attachments"][0]["fields"][0]["value"]}''",
            callback_id: "task completed",
            attachment_type: "default",
          }
        ]
      )

      #UPDATE OLD MESSAGE
      $teams[team_id]['client'].chat_update(
        token: data["token"],
        channel: data["channel"]["id"],
        ts: data["original_message"]["ts"],
        text: "Completed Task",
        attachments: [
          {
            color: "#3c0783",
            callback_id: "disabled",
            attachment_type: "default",
            fields: [
              {title: "Task Description", value: "#{data["original_message"]["attachments"][0]["fields"][0]["value"]}"},
              {title: "Assigned by:", value: "#{data["original_message"]["attachments"][0]["fields"][1]["value"]}"}
            ],
            actions: [
              {
                name: "option",
                value: "completed",
                text: ":white_check_mark: Completed",
                type: "button"
              }
            ]
          }
        ]
      )
    end
  end

  def self.send_tutorial(team_id, user_id)
    channel = $teams[team_id]['client'].im_open(user: user_id)

    $teams[team_id]['client'].chat_postMessage(
      as_user: 'true',
      channel: channel.channel.id,
      text: "Tutorial",
      attachments: [
        {
          color: "#3c0783",
          title: "Welcome to DonutBot!",
          text: "DonutBot is a helper app for assigning tasks to other users.\n\nTo assign a task, simply send a direct message to DonutBot. In the body of the message, tag the user you'd like to assign the task to followed by the task description in plain text.",
          callback_id: "tutorial",
          attachment_type: "default"
        },
        {
          color: "#3c0783",
          text: "You can include as many tasks to as many users as you like, simply add another tag and task after the first.\n\nExample: '@Will Take out the trash. @Molly Do the dishes.'",
          callback_id: "tutorial",
          attachment_type: "default"
        }
      ]
    )
  end
end
