require File.expand_path('../../../spec_helper.rb', __FILE__)

describe Fission::Command::Start do
  include_context 'command_setup'

  before do
    @target_vm = ['foo']
    Fission::VM.stub(:new).and_return(@vm_mock)

    @start_response_mock = mock('start_response')

    @vm_mock.stub(:name).and_return(@target_vm.first)
  end

  describe 'execute' do
    subject { Fission::Command::Start }

    it_should_not_accept_arguments_of [], 'start'

    it 'should output an error and exit if there was an error starting the vm' do
      @start_response_mock.stub_as_unsuccessful

      @vm_mock.should_receive(:start).and_return(@start_response_mock)

      command = Fission::Command::Start.new @target_vm
      lambda { command.execute }.should raise_error SystemExit

      @string_io.string.should match /Starting '#{@target_vm.first}'/
      @string_io.string.should match /There was a problem starting the VM.+it blew up.+/m
    end

    describe 'with --headless' do
      it 'should start the vm headless' do
        @start_response_mock.stub_as_successful

        @vm_mock.should_receive(:start).and_return(@start_response_mock)

        command = Fission::Command::Start.new @target_vm << '--headless'
        command.execute

        @string_io.string.should match /Starting '#{@target_vm.first}'/
          @string_io.string.should match /VM '#{@target_vm.first}' started/
      end
    end

  end

  describe 'help' do
    it 'should output info for this command' do
      output = Fission::Command::Start.help

      output.should match /start vm_name \[options\]/
      output.should match /--headless/
    end
  end
end
