#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class CheckState

      include Sandstorm::Records::RedisRecord

      define_attributes :state     => :string,
                        :summaries => :list,
                        :details   => :list,
                        :timestamp => :timestamp,
                        :notified  => :boolean,
                        :last_notification_count => :integer

      index_by :state, :notified

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :states

      has_many :current_notifications, :class_name => 'Flapjack::Data::Notification'
      has_many :previous_notifications, :class_name => 'Flapjack::Data::Notification'


      def self.ok_states
        ['ok']
      end

      # TODO add 'down', 'unreachable' per event.rb in Flapjack v1?
      def self.failing_states
        ['critical', 'warning', 'unknown']
      end

      def self.all_states
        self.failing_states + self.ok_states
      end

      validate :state, :presence => true, :inclusion => { :in => self.all_states }
      validate :timestamp, :presence => true

    end
  end
end