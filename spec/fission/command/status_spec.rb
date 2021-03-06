require File.expand_path('../../../spec_helper.rb', __FILE__)

describe Fission::Command::Status do
  include_context 'command_setup'

  before do
    @vms_status = { 'foo' => 'running',
                    'bar' => 'suspended',
                    'baz' => 'not running' }
    @all_status_response_mock = mock('response')
  end

  describe 'execute' do
    before do
      Fission::VM.should_receive(:all_with_status).
                  and_return(@all_status_response_mock)
    end

    describe 'when successful' do
      before do
        @all_status_response_mock.stub_as_successful @vms_status
      end

      it 'should output the VMs and their status' do
        command = Fission::Command::Status.new
        command.execute

        @string_io.string.should match /foo.+\[running\]/
        @string_io.string.should match /bar.+\[suspended\]/
        @string_io.string.should match /baz.+\[not running\]/
      end
    end

    describe 'when unsuccessful' do
      before do
        @all_status_response_mock.stub_as_unsuccessful
      end

      it 'should output an error and exit if there was an error getting the list of running VMs' do
        command = Fission::Command::Status.new
        lambda { command.execute }.should raise_error SystemExit

        @string_io.string.should match /There was an error getting the status of the VMs.+it blew up/m
      end
    end
  end

  describe 'help' do
    it 'should output info for this command' do
      output = Fission::Command::Status.help

      output.should match /status/
    end
  end
end
