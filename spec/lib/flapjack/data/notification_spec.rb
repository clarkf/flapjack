require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true, :logger => true do

  let(:event)   { double(Flapjack::Data::Event) }

  let(:check)       { double(Flapjack::Data::Check) }
  let(:entity)      { double(Flapjack::Data::Entity) }

  let(:contact) { double(Flapjack::Data::Contact) }

  let(:timezone) { double('timezone') }

  it "generates a notification for an event"

  it "generates messages for contacts" do
    notification = Flapjack::Data::Notification.new(
      :state_duration    => 16,
      :severity          => 'critical',
      :type              => 'problem',
      :time              => Time.now,
      :duration          => nil,
      :tags              => Set.new
    )
    expect(notification.save).to be_truthy
    expect(notification).to receive(:check).exactly(5).times.and_return(check)

    expect(check).to receive(:id).twice.and_return('abcde')
    expect(entity).to receive(:name).exactly(3).times.and_return('example.com')
    expect(check).to receive(:entity).exactly(3).times.and_return(entity)
    expect(check).to receive(:name).twice.and_return('ping')

    expect(notification).to receive(:state).exactly(6).times.and_return('critical')

    alerting_checks_1 = double('alerting_checks_1')
    expect(alerting_checks_1).to receive(:exists?).with('abcde').and_return(false)
    expect(alerting_checks_1).to receive(:<<).with(check)
    expect(alerting_checks_1).to receive(:count).and_return(1)

    alerting_checks_2 = double('alerting_checks_1')
    expect(alerting_checks_2).to receive(:exists?).with('abcde').and_return(false)
    expect(alerting_checks_2).to receive(:<<).with(check)
    expect(alerting_checks_2).to receive(:count).and_return(1)

    medium_1 = double(Flapjack::Data::Medium)
    expect(medium_1).to receive(:type).and_return('email')
    expect(medium_1).to receive(:address).and_return('abcde@example.com')
    expect(medium_1).to receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_1)
    expect(medium_1).to receive(:clean_alerting_checks).and_return(0)
    expect(medium_1).to receive(:rollup_threshold).exactly(3).times.and_return(10)

    medium_2 = double(Flapjack::Data::Medium)
    expect(medium_2).to receive(:type).and_return('sms')
    expect(medium_2).to receive(:address).and_return('0123456789')
    expect(medium_2).to receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_2)
    expect(medium_2).to receive(:clean_alerting_checks).and_return(0)
    expect(medium_2).to receive(:rollup_threshold).exactly(3).times.and_return(10)

    alert_1 = double(Flapjack::Data::Alert)
    expect(alert_1).to receive(:save).and_return(true)
    alert_2 = double(Flapjack::Data::Alert)
    expect(alert_2).to receive(:save).and_return(true)

    expect(Flapjack::Data::Alert).to receive(:new).
      with(:rollup => nil, :acknowledgement_duration => nil,
        :state => "critical", :state_duration => 16,
        :notification_type => 'problem').and_return(alert_1)

    expect(Flapjack::Data::Alert).to receive(:new).
      with(:rollup => nil, :acknowledgement_duration => nil,
        :state => "critical", :state_duration => 16,
        :notification_type => 'problem').and_return(alert_2)

    medium_alerts_1 = double('medium_alerts_1')
    expect(medium_alerts_1).to receive(:<<).with(alert_1)
    expect(medium_1).to receive(:alerts).and_return(medium_alerts_1)

    medium_alerts_2 = double('medium_alerts_1')
    expect(medium_alerts_2).to receive(:<<).with(alert_2)
    expect(medium_2).to receive(:alerts).and_return(medium_alerts_2)

    check_alerts = double('check_alerts_1')
    expect(check_alerts).to receive(:<<).with(alert_1)
    expect(check_alerts).to receive(:<<).with(alert_2)
    expect(check).to receive(:alerts).twice.and_return(check_alerts)

    expect(contact).to receive(:id).and_return('23')
    expect(contact).to receive(:notification_rules).and_return([])
    all_media = double('all_media', :all => [medium_1, medium_2], :empty? => false)
    expect(all_media).to receive(:each).and_yield(medium_1).
                                    and_yield(medium_2).
                                    and_return([alert_1, alert_2])
    expect(contact).to receive(:media).and_return(all_media)

    alerts = notification.alerts([contact], :default_timezone => timezone,
      :logger => @logger)
    expect(alerts).not_to be_nil
    expect(alerts.size).to eq(2)
    expect(alerts).to eq([alert_1, alert_2])
  end

end
