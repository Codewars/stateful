require 'spec_helper'
require './lib/stateful'

class Kata
  include Stateful

  attr_accessor :approved_by, :ready_score, :published_at, :state_changes

  def initialize
    @ready_score = 0
    @state_changes = 0
  end

  stateful  default: :draft,
            events: [:publish, :unpublish, :approve, :retire],
            states: {
                :draft => :beta,
                published: {
                    beta: {
                        :needs_feedback => [:draft, :needs_approval],
                        :needs_approval => [:draft, :approved]
                    },
                    :approved => :retired
                },
                :retired => nil
            }

  stateful :merge_status, default: :na, events: [:merge, :approve_merge, :reject_merge], states: {
      na: :pending,
      pending: [:approved, :rejected],
      approved: nil,
      rejected: :pending
  }

  after_state_change do |doc|
    doc.state_changes += 1
  end

  def vote(ready)
    @ready_score += ready ? 1 : -1

    # votes only affect state when in beta
    if beta?
      if enough_votes_for_approval? and needs_feedback?
        change_state(:needs_approval)
      elsif not enough_votes_for_approval? and needs_approval?
        change_state(:needs_feedback)
      end
    end
  end

  def publish
    change_state(enough_votes_for_approval? ? :needs_approval : :needs_feedback) do
      @published_at = Time.now
    end
  end

  def unpublish
    change_state(:draft)
  end

  def approve(approved_by)
    change_state(:approved) do
      @approved_by = approved_by
    end
  end

  def retire
    change_state(:retire)
  end

  def enough_votes_for_approval?
    ready_score >= 10
  end
end

describe Kata do
  let(:kata) {Kata.new}

  it 'should support state_infos' do
    Kata.state_infos.should_not be_nil
    Kata.merge_status_infos.should_not be_nil
  end

  it 'should support default state' do
    kata.state.should == :draft
    kata.merge_status.should == :na
  end

  it 'should support state_info' do
    kata.state_info.should_not be_nil
    kata.state_info.name.should == :draft

    # custom names
    kata.merge_status_info.should_not be_nil
    kata.merge_status_info.name.should == :na
  end

  it 'should support simple boolean helper methods' do
    kata.draft?.should be_true
    kata.published?.should be_false
    kata.state = :needs_feedback
    kata.published?.should be_true

    # custom state names
    kata.merge_status_na?.should be_true
    kata.merge_status_approved?.should be_false
    kata.merge_status = :approved
    kata.merge_status_approved?.should be_true
  end

  context 'change_state' do
    it 'should raise error when an invalid transition state is provided' do
      expect{kata.send(:change_state!, :retired)}.to raise_error
      expect{kata.send(:change_merge_status!, :approved)}.to raise_error
    end

    it 'should raise error when a group state is provided' do
      expect{kata.send(:change_state!, :beta)}.to raise_error
    end

    it 'should return false when state is the same' do
      kata.send(:change_state, :draft).should be_false
    end

    it 'should support state_valid?' do
      kata.state_valid?.should be_true
      kata.merge_status_valid?.should be_true
    end

    it 'should change the state when a proper state is provided' do
      kata.send(:change_state, :needs_feedback).should be_true
      kata.state.should == :needs_feedback
      kata.send(:change_state, :needs_approval).should be_true
      kata.state.should == :needs_approval
      kata.send(:change_state, :draft).should be_true
      kata.state.should == :draft
      kata.send(:change_state, :needs_approval).should be_true
      kata.send(:change_state, :approved).should be_true
      kata.state.should == :approved

      # custom
      kata.send(:change_merge_status, :approved).should be_false
      kata.send(:change_merge_status, :pending).should be_true
      kata.merge_status.should == :pending
    end

    it 'should support calling passed blocks when state is valid' do
      kata.published_at.should be_nil
      kata.publish
      kata.published_at.should_not be_nil
    end

    it 'should support ingoring passed blocked when state is not valid' do
      kata.approve('test')
      kata.approved?.should be_false
      kata.approved_by.should be_nil
    end

    it 'should support after callbacks methods' do
      kata.publish
      kata.state_changes.should == 1
    end

    it 'should support can_transition_to_state?' do
      kata.can_transition_to_state?(:needs_feedback).should be_true
      kata.can_transition_to_state?(:approved).should be_false

      # custom states
      kata.can_transition_to_merge_status?(:pending).should be_true
      kata.can_transition_to_merge_status?(:approved).should be_false
    end
  end

  describe Stateful::StateInfo do
    it 'should support is?' do
      Kata.state_infos[:draft].is?(:draft).should be_true
      Kata.state_infos[:needs_feedback].is?(:published).should be_true
      Kata.state_infos[:needs_feedback].is?(:beta).should be_true
      Kata.state_infos[:approved].is?(:published).should be_true
      Kata.state_infos[:approved].is?(:beta).should be_false
      Kata.state_infos[:retired].is?(:beta).should be_false

      # custom
      Kata.merge_status_infos[:na].is?(:na).should be_true
    end

    it 'should support expanded to transitions' do
      Kata.state_infos[:draft].to_transitions.should == [:needs_feedback, :needs_approval]
      Kata.state_infos[:needs_approval].to_transitions.should == [:draft, :approved]

      Kata.state_infos[:retired].to_transitions.should be_empty
    end

    it 'should support can_transition_to?' do
      Kata.state_infos[:draft].can_transition_to?(:needs_feedback).should be_true
      Kata.state_infos[:draft].can_transition_to?(:approved).should be_false

      Kata.merge_status_infos[:na].can_transition_to?(:pending).should be_true
    end
  end
end