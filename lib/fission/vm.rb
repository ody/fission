require 'fission/leasesfile'

module Fission
  class VM
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def create_snapshot(name)
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} snapshot "
      command << "#{conf_file_response.data.gsub ' ', '\ '} \"#{name}\" 2>&1"
      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus
      response.output = output unless response.successful?

      response
    end

    def revert_to_snapshot(name)
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} revertToSnapshot "
      command << "#{conf_file_response.data.gsub ' ', '\ '} \"#{name}\" 2>&1"
      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus
      response.output = output unless response.successful?

      response
    end

    def snapshots
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} listSnapshots "
      command << "#{conf_file_response.data.gsub ' ', '\ '} 2>&1"
      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus

      if response.successful?
        snaps = output.split("\n").select { |s| !s.include? 'Total snapshots:' }
        response.data = snaps.map { |s| s.strip }
      else
        response.output = output
      end

      response
    end

    def start(args={})
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} start "
      command << "#{conf_file_response.data.gsub ' ', '\ '} "

      if !args[:headless].blank? && args[:headless]
        command << "nogui 2>&1"
      else
        command << "gui 2>&1"
      end

      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus
      response.output = output unless response.successful?

      response
    end

    def stop
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} stop "
      command << "#{conf_file_response.data.gsub ' ', '\ '} 2>&1"
      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus
      response.output = output unless response.successful?

      response
    end

    def halt
      command = "#{Fission.config.attributes['vmrun_cmd']} stop #{conf_file.gsub ' ', '\ '} hard 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "VM halted"
      else
        Fission.ui.output "There was a problem halting the VM.  The error was:\n#{output}"
      end
    end

    def resume
      if state=="suspended"
        start
      end
    end

    def state
      return "not created" unless exists?

      if VM.all_running.include?(name)
        return "running"
      else
        # It coud be suspended
        suspend_filename=File.join(File.dirname(conf_file), File.basename(conf_file,".vmx")+".vmem")
        if File.exists?(suspend_filename)
          return "suspended"
        else
          return "not running"
        end
      end
    end

    # Retrieve the first mac address for a vm
    # This will only retrieve the first auto generate mac address
    #
    # Usage :
    # > vm=Fission::VM.new("lucid64")
    # > vm.mac_address
    # => "00:0c:29:26:49:2c"
    def mac_address
      unless File.exists?(conf_file)
        return nil
      else
        line=File.new(conf_file).grep(/^ethernet0.generatedAddress =/)
        if line.nil?
          #Fission.ui.output "Hmm, the vmx file #{conf_file} does not contain a generated mac address "
        end
        address=line.first.split("=")[1].strip.split(/\"/)[1]
        return address
      end
    end

    # Retrieve the ip address for a vm.
    # This will only look for dynamically assigned ip address via vmware dhcp
    #
    # > vm=Fission::VM.new("lucid64")
    # > vm.ip_address
    #  => "172.16.44.139"
    #
    # Some pointers with extra info
    # - http://nileshk.com/2009/06/24/vmware-fusion-nat-dhcp-and-port-forwarding.html
    # - http://works13.com/blog/mac/ssh-your-arch-linux-vm-in-vmware-fusion.htm
    #
    #       /var/db/vmware/vmnet-dhcpd-vmnet8.leases
    #
    #       lease 172.16.44.134 {
    #         starts 4 2011/07/28 15:54:41;
    #         ends 4 2011/07/28 16:24:41;
    #         hardware ethernet 00:0c:29:54:06:5c;
    #       }
    #
    def ip_address
      if state!="running"
        return nil
      end
      unless mac_address.nil?
        lease=LeasesFile.new("/var/db/vmware/vmnet-dhcpd-vmnet8.leases").find_lease_by_mac(mac_address)
        if lease.nil?
          return nil
        else
          return lease.ip
        end
      else
        # No mac address was found for this machine so we can't calculate the ip-address
        return nil
      end
    end

    def suspend
      conf_file_response = conf_file
      unless conf_file_response.successful?
        return conf_file_response
      end

      command = "#{Fission.config.attributes['vmrun_cmd']} suspend "
      command << "#{conf_file_response.data.gsub ' ', '\ '} 2>&1"
      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus
      response.output = output unless response.successful?
      response
    end

    def conf_file
      vmx_path = File.join(self.class.path(@name), "*.vmx")
      conf_files = Dir.glob(vmx_path)
      response = Response.new

      case conf_files.count
      when 0
        response.code = 1
        response.output = "Unable to find a config file for VM '#{@name}' (in '#{vmx_path}')"
      when 1
        response.code = 0
        response.data = conf_files.first
      else
        if conf_files.include?(File.join(File.dirname(vmx_path), "#{@name}.vmx"))
          response.code = 0
          response.data = File.join(File.dirname(vmx_path), "#{@name}.vmx")
        else
          response.code = 1
          output = "Multiple config files found for VM '#{@name}' ("
          output << conf_files.sort.map { |f| "'#{File.basename(f)}'" }.join(', ')
          output << " in '#{File.dirname(vmx_path)}')"
          response.output = output
        end
      end

      response
    end

    def self.all
      vm_dirs = Dir[File.join Fission.config.attributes['vm_dir'], '*.vmwarevm'].select do |d|
        File.directory? d
      end

      response = Fission::Response.new :code => 0
      response.data = vm_dirs.map { |d| File.basename d, '.vmwarevm' }

      response
    end

    def self.all_running
      command = "#{Fission.config.attributes['vmrun_cmd']} list"

      output = `#{command}`

      response = Fission::Response.new :code => $?.exitstatus

      if response.successful?
        vms = output.split("\n").select do |vm|
          vm.include?('.vmx') && File.exists?(vm) && File.extname(vm) == '.vmx'
        end

        response.data = vms.map { |vm| File.basename(File.dirname(vm), '.vmwarevm') }
      else
        response.output = output
      end

      response
    end

    def exists?
      response=Fission::VM.exists?(name)
      return response.data
    end

    def self.exists?(vm_name)
      Response.new :code => 0, :data => (File.directory? path(vm_name))
    end

    def self.path(vm_name)
      File.join Fission.config.attributes['vm_dir'], "#{vm_name}.vmwarevm"
    end

    def self.clone(source_vm, target_vm)
      FileUtils.cp_r path(source_vm), path(target_vm)

      rename_vm_files source_vm, target_vm
      update_config source_vm, target_vm

      response = Response.new :code => 0
    end


    def self.delete(vm_name)
      FileUtils.rm_rf path(vm_name)
      Fission::Metadata.delete_vm_info(path(vm_name))

      Response.new :code => 0
    end


    private
    def self.rename_vm_files(from, to)
      files_to_rename(from, to).each do |file|
        text_to_replace = File.basename(file, File.extname(file))

        if File.extname(file) == '.vmdk'
          if file.match /\-s\d+\.vmdk/
            text_to_replace = file.partition(/\-s\d+.vmdk/).first
          end
        end

        unless File.exists?(File.join(path(to), file.gsub(text_to_replace, to)))
          FileUtils.mv File.join(path(to), file),
            File.join(path(to), file.gsub(text_to_replace, to))
        end
      end
    end

    def self.files_to_rename(from, to)
      files_which_match_source_vm = []
      other_files = []

      Dir.entries(path(to)).each do |f|
        unless f == '.' || f == '..'
          f.include?(from) ? files_which_match_source_vm << f : other_files << f
        end
      end

      files_which_match_source_vm + other_files
    end

    def self.vm_file_extensions
      ['.nvram', '.vmdk', '.vmem', '.vmsd', '.vmss', '.vmx', '.vmxf']
    end

    def self.update_config(from, to)
      ['.vmx', '.vmxf', '.vmdk'].each do |ext|
        file = File.join path(to), "#{to}#{ext}"

        unless File.binary?(file)
          text = (File.read file).gsub from, to
          File.open(file, 'w'){ |f| f.print text }
        end

      end

      # Rewrite vmx file to avoid messages
      new_vmx_file=File.open(File.join(path(to),"#{to}.vmx"),'r')

      content=new_vmx_file.read

      # Filter out other values
      content=content.gsub(/^tools.remindInstall.*\n/, "")
      content=content.gsub(/^uuid.action.*\n/,"").strip

      # Remove generate mac addresses
      content=content.gsub(/^ethernet.+generatedAddress.*\n/,"").strip

      # Add the correct values
      content=content+"\ntools.remindInstall = \"FALSE\"\n"
      content=content+"uuid.action = \"create\"\n"

      # Now rewrite the vmx file
      File.open(new_vmx_file,'w'){ |f| f.print content}

    end

  end
end
