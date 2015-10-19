describe Proposal do
  describe 'CLIENT_MODELS' do
    it "contains multiple models" do
      expect(Proposal::CLIENT_MODELS.size).to_not eq(0)
      Proposal::CLIENT_MODELS.each do |model|
        expect(model.ancestors).to include(ActiveRecord::Base)
      end
    end
  end

  describe '#currently_awaiting_approvers' do
    it "gives a consistently ordered list when in parallel" do
      proposal = create(:proposal, :with_parallel_approvers)
      approver1, approver2 = proposal.approvers
      expect(proposal.currently_awaiting_approvers).to eq([approver1, approver2])

      proposal.individual_approvals.first.update_attribute(:position, 5)
      expect(proposal.currently_awaiting_approvers).to eq([approver2, approver1])
    end

    it "gives only the first approver when linear" do
      proposal = create(:proposal, :with_serial_approvers)
      approver1, approver2 = proposal.approvers
      expect(proposal.currently_awaiting_approvers).to eq([approver1])

      proposal.individual_approvals.first.approve!
      expect(proposal.currently_awaiting_approvers).to eq([approver2])
    end
  end

  describe '#delegate_with_default' do
    it "returns the delegated value" do
      proposal = Proposal.new
      client_data = double(some_prop: 'foo')
      expect(proposal).to receive(:client_data).and_return(client_data)

      result = proposal.delegate_with_default(:some_prop)
      expect(result).to eq('foo')
    end

    it "returns the default when the delegated value is #blank?" do
      proposal = Proposal.new
      client_data = double(some_prop: '')
      expect(proposal).to receive(:client_data).and_return(client_data)

      result = proposal.delegate_with_default(:some_prop) { 'foo' }
      expect(result).to eq('foo')
    end

    it "returns the default when there is no method on the delegate" do
      proposal = Proposal.new
      expect(proposal).to receive(:client_data).and_return(double)

      result = proposal.delegate_with_default(:some_prop) { 'foo' }
      expect(result).to eq('foo')
    end
  end

  describe '#name' do
    it "returns the #public_identifier by default" do
      proposal = Proposal.new
      expect(proposal).to receive(:id).and_return(6)

      expect(proposal.name).to eq('Request #6')
    end
  end

  describe '#users' do
    it "returns all approvers, observers, and the requester" do
      requester = create(:user)
      proposal = create(:proposal, :with_parallel_approvers, :with_observers, requester: requester)

      expect(proposal.users.map(&:id).sort).to eq([
        requester.id,
        proposal.approvers.first.id, proposal.approvers.second.id,
        proposal.observers.first.id, proposal.observers.second.id
      ].sort)
    end

    it "returns only the rquester when it has no other users" do
      proposal = create(:proposal)
      expect(proposal.users).to eq([proposal.requester])
    end

    it "removes duplicates" do
      requester = create(:user)
      proposal = create(:proposal, requester: requester)
      proposal.add_observer(requester.email_address)
      expect(proposal.users).to eq [requester]
    end

    it "adds observer from user object" do
      observer = create(:user)
      proposal = create(:proposal, requester: observer)
      proposal.add_observer(observer)
      expect(proposal.users).to eq [observer]
    end
  end

  describe '#root_approval=' do
    let(:approver1) { create(:user) }
    let(:approver2) { create(:user) }
    let(:approver3) { create(:user) }

    it 'sets initial approvers' do
      proposal = create(:proposal)
      approvers = 3.times.map{ create(:user) }
      individuals = approvers.map{ |u| Approvals::Individual.new(user: u) }

      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      expect(proposal.approvals.count).to be 4
      expect(proposal.approvers).to eq approvers
    end

    it 'initates parallel' do
      proposal = create(:proposal, flow: 'parallel')
      individuals = [approver1, approver2, approver3].map{ |u| Approvals::Individual.new(user: u)}

      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      expect(proposal.approvers.count).to be 3
      expect(proposal.approvals.count).to be 4
      expect(proposal.individual_approvals.actionable.count).to be 3
      expect(proposal.approvals.actionable.count).to be 4
    end

    it 'initates linear' do
      proposal = create(:proposal, flow: 'linear')
      individuals = [approver1, approver2, approver3].map{ |u| Approvals::Individual.new(user: u)}

      proposal.root_approval = Approvals::Serial.new(child_approvals: individuals)

      expect(proposal.approvers.count).to be 3
      expect(proposal.approvals.count).to be 4
      expect(proposal.individual_approvals.actionable.count).to be 1
      expect(proposal.approvals.actionable.count).to be 2
    end

    it 'fixes modified parallel proposal approvals' do
      proposal = create(:proposal, flow: 'parallel')
      individuals = [Approvals::Individual.new(user: approver1)]
      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      expect(proposal.approvals.actionable.count).to be 2
      expect(proposal.individual_approvals.actionable.count).to be 1

      individuals = individuals + [approver2, approver3].map{ |u| Approvals::Individual.new(user: u)}
      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      expect(proposal.approvals.actionable.count).to be 4
      expect(proposal.individual_approvals.actionable.count).to be 3
    end

    it 'fixes modified linear proposal approvals' do
      proposal = create(:proposal, flow: 'linear')
      approver1, approver2, approver3 = 3.times.map{ create(:user) }
      individuals = [approver1, approver2].map{ |u| Approvals::Individual.new(user: u) }
      proposal.root_approval = Approvals::Serial.new(child_approvals: individuals)

      expect(proposal.approvals.actionable.count).to be 2
      expect(proposal.individual_approvals.actionable.count).to be 1

      individuals.first.approve!
      individuals[1] = Approvals::Individual.new(user: approver3)
      proposal.root_approval = Approvals::Serial.new(child_approvals: individuals)

      expect(proposal.approvals.approved.count).to be 1
      expect(proposal.approvals.actionable.count).to be 2
      expect(proposal.individual_approvals.actionable.count).to be 1
      expect(proposal.individual_approvals.actionable.first.user).to eq approver3
    end

    it 'does not modify a full approved parallel proposal' do
      proposal = create(:proposal, flow: 'parallel')
      individuals = [approver1, approver2].map{ |u| Approvals::Individual.new(user: u)}
      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      proposal.individual_approvals.first.approve!
      proposal.individual_approvals.second.approve!

      expect(proposal.approvals.actionable).to be_empty
    end

    it 'does not modify a full approved linear proposal' do
      proposal = create(:proposal, flow: 'linear')
      individuals = [approver1, approver2].map{ |u| Approvals::Individual.new(user: u)}
      proposal.root_approval = Approvals::Serial.new(child_approvals: individuals)

      proposal.individual_approvals.first.approve!
      proposal.individual_approvals.second.approve!

      expect(proposal.approvals.actionable).to be_empty
    end

    it 'deletes approvals' do
      proposal = create(:proposal, :with_parallel_approvers)
      approval1, approval2 = proposal.individual_approvals
      proposal.root_approval = Approvals::Serial.new(child_approvals: [approval2])

      expect(Approval.exists?(approval1.id)).to be false
    end
  end

  describe '#reset_status' do
    it 'sets status as approved if there are no approvals' do
      proposal = create(:proposal)
      expect(proposal.pending?).to be true
      proposal.reset_status()
      expect(proposal.approved?).to be true
    end

    it 'sets status as cancelled if the proposal has been cancelled' do
      proposal = create(:proposal, :with_parallel_approvers)
      proposal.individual_approvals.first.approve!
      expect(proposal.pending?).to be true
      proposal.cancel!

      proposal.reset_status()
      expect(proposal.cancelled?).to be true
    end

    it 'reverts to pending if an approval is added' do
      proposal = create(:proposal, :with_parallel_approvers)
      proposal.individual_approvals.first.approve!
      proposal.individual_approvals.second.approve!
      expect(proposal.reload.approved?).to be true
      individuals = proposal.root_approval.child_approvals + [Approvals::Individual.new(user: create(:user))]
      proposal.root_approval = Approvals::Parallel.new(child_approvals: individuals)

      proposal.reset_status()
      expect(proposal.pending?).to be true
    end

    it 'does not move out of the pending state unless all are approved' do
      proposal = create(:proposal, :with_parallel_approvers)
      proposal.reset_status()
      expect(proposal.pending?).to be true
      proposal.individual_approvals.first.approve!

      proposal.reset_status()
      expect(proposal.pending?).to be true
      proposal.individual_approvals.second.approve!

      proposal.reset_status()
      expect(proposal.approved?).to be true
    end
  end

  describe "scopes" do
    let(:statuses) { %w(pending approved cancelled) }
    let!(:proposals) { statuses.map{|status| create(:proposal, status: status) } }

    it "returns the appropriate proposals by status" do
      statuses.each do |status|
        expect(Proposal.send(status).pluck(:status)).to eq([status])
      end
    end

    describe '.closed' do
      it "returns approved and and cancelled proposals" do
        expect(Proposal.closed.pluck(:status).sort).to eq(%w(approved cancelled))
      end
    end
  end

  describe '#restart' do
    it "creates new API tokens" do
      proposal = create(:proposal, :with_parallel_approvers)
      proposal.individual_approvals.each(&:create_api_token!)
      expect(proposal.api_tokens.size).to eq(2)

      proposal.restart!

      expect(proposal.api_tokens.unscoped.expired.size).to eq(2)
      expect(proposal.api_tokens.unexpired.size).to eq(2)
    end
  end

  describe '#add_observer' do
    let(:proposal) { create(:proposal) }
    let(:observer) { create(:user) }
    let(:observer_email) { observer.email_address }
    let(:user) { create(:user) }

    it 'adds an observer to the proposal' do
      expect(proposal.observers).to be_empty
      proposal.add_observer(observer_email)
      expect(proposal.observers).to eq [observer]
    end

    it 'adds a comment and sends a comment email when there is an adder and observation reason' do
      reason = "this is required"

      expect {
        proposal.add_observer(observer_email, user, reason)
      }.to change { deliveries.length }.from(0).to(1)

      expect(proposal.comments.count).to eq 1
    end

    it 'sends an observer email when there is an adder but no reason' do
      expect {
        proposal.add_observer(observer_email, user, nil)
      }.to change { deliveries.length }.from(0).to(1)
    end

    context 'with an adding user' do
      context 'without a reason' do
        it 'does not add a comment' do
          expect(proposal.comments).to be_empty
          proposal.add_observer(observer_email, user)
          expect(proposal.comments).to be_empty
        end
      end

      context 'with a reason' do
        let(:reason) { 'my mate, innit' }

        it 'adds an update comment mentioning the reason' do
          expect(proposal.comments).to be_empty
          proposal.add_observer(observer_email, user, reason)
          expect(proposal.comments.length).to eq 1
          expect(proposal.comments.first).to be_update_comment
          expect(proposal.comments.first.comment_text).to include reason
        end
      end
    end
  end
end
