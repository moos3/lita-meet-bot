require "spec_helper"

describe Lita::Handlers::Meet, lita_handler: true do
  it { is_expected.to route_command("start standup").with_authorization_for(:standup_admins).to(:start_standup) }
  it { is_expected.to route_command("standup response 1:a2:b3:c").to(:store_response) }
  it { is_expected.to route_command("standup playback #{DateTime.now.strftime("%Y%m%d")}").to(:playback)}
  it { is_expected.to route_command("standup play").to(:update_room)}


  before do
    @larry = Lita::User.create(111, name: "larry")
    @moe = Lita::User.create(112, name: "moe")
    @curly = Lita::User.create(113, name: "curly")
    people = [@larry, @moe, @curly]
    registry.config.handlers.meet.time_to_respond = 100  #Not async for testing
    registry.config.handlers.meet.api_key = 'v8NPE7SQ0G1WYmiDVIhaWL39CcHhdKXuNK1oDVWHSFH6rQVdupwrjlnF4ZY5u7bo'
    registry.config.handlers.meet.enable_http = 'on'
    people.each { |person| robot.auth.add_user_to_group!(person, :standup_participants) }
    people.each { |person| robot.auth.add_user_to_group!(person, :standup_admins) }
  end

  describe '#start_standup' do
    it 'messages each user and prompts for stand up options' do
      send_command("start standup", as: @larry)
      expect(replies.size).to eq(6) #larry, moe, and curly
    end

    describe 'nagging for responses' do
      before do
        registry.config.handlers.meet.nag_frequency = 1 # seconds
        send_command("start standup", as: @larry)
      end
      it 'nags each user on nag frequency' do

      end
    end
  end

  describe '#process_standup' do
    it "accepts responses" do
      send_command("start standup", as: @larry)
      send_command("standup response 1: linguistics 2: more homework 3: being in seattle", as: @moe)
      send_command("standup response 1: stitchfix 2: more stitchfix 3: gaining weight", as: @curly)
      send_command("standup response 1: lita 2: Rust else 3: nothing", as: @larry)
      sleep(2);
    end
  end
end
