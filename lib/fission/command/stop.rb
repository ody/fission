module Fission
  class Command
    class Stop < Command

      def initialize(args=[])
        super
      end

      def execute
        unless @args.count == 1
          Fission.ui.output self.class.help
          Fission.ui.output ""
          Fission.ui.output_and_exit "Incorrect arguments for stop command", 1
        end

        vm_name = @args.first


        unless Fission::VM.exists? vm_name
          Fission.ui.output_and_exit "Unable to find the VM #{vm_name} (#{Fission::VM.path(vm_name)})", 1 
        end

        vm = Fission::VM.new vm_name

        response = Fission::VM.all_running

          unless vm.is_running?
            Fission.ui.output ''
            Fission.ui.output_and_exit "VM '#{vm_name}' is not running", 0
          end
        #TODO
        #  Fission.ui.output_and_exit "There was an error determining if the VM is already running.  The error was:\n#{response.output}", response.code

        Fission.ui.output "Stopping '#{vm_name}'"
        task  = vm.stop

        if task.successful?
          Fission.ui.output "VM '#{vm_name}' stopped"
        else
          Fission.ui.output_and_exit "There was an error stopping the VM.  The error was:\n#{response.output}", response.code
        end
      end

      def option_parser
        optparse = OptionParser.new do |opts|
          opts.banner = "\nstop usage: fission stop vm"
        end

        optparse
      end

    end
  end
end
