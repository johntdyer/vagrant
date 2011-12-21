require 'vagrant/util/subprocess'

module Vagrant
  module Driver
    # This class contains the logic to drive VirtualBox.
    class VirtualBox
      # Include this so we can use `Subprocess` more easily.
      include Vagrant::Util

      # The version of virtualbox that is running.
      attr_reader :version

      def initialize(uuid)
        @uuid = uuid

        # Read and assign the version of VirtualBox we know which
        # specific driver to instantiate.
        begin
          @version = read_version
        rescue Subprocess::ProcessFailedToStart
          # This means that VirtualBox was not found, so we raise this
          # error here.
          raise Errors::VirtualBoxNotDetected
        end
      end

      # This clears the forwarded ports that have been set on the
      # virtual machine.
      def clear_forwarded_ports
        args = []
        read_forwarded_ports(@uuid).each do |nic, name, _, _|
          args.concat(["--natpf#{nic}", "delete", name])
        end

        execute("modifyvm", @uuid, *args) if !args.empty?
      end

      # This deletes the VM with the given name.
      def delete
        execute("unregistervm", @uuid, "--delete")
      end

      # Forwards a set of ports for a VM.
      #
      # This will not affect any previously set forwarded ports,
      # so be sure to delete those if you need to.
      #
      # The format of each port hash should be the following:
      #
      #     {
      #       :name => "foo",
      #       :host_port => 8500,
      #       :guest_port => 80,
      #       :adapter => 1,
      #       :protocol => "tcp"
      #     }
      #
      # Note that "adapter" and "protocol" are optional and will default
      # to 1 and "tcp" respectively.
      #
      # @param [Array<Hash>] ports An array of ports to set. See documentation
      #   for more information on the format.
      def forward_ports(ports)
        args = []
        ports.each do |options|
          pf_builder = [options[:name],
                        options[:protocol] || "tcp",
                        "",
                        options[:host_port],
                        "",
                        options[:guest_port]]

          args.concat(["--natpf#{options[:adapter] || 1}",
                       pf_builder.join(",")])
        end

        execute("modifyvm", @uuid, *args)
      end

      # Imports the VM with the given path to the OVF file. It returns
      # the UUID as a string.
      def import(ovf, name)
        execute("import", ovf, "--vsys", "0", "--vmname", name)
        output = execute("list", "vms")
        if output =~ /^"#{name}" {(.+?)}$/
          return $1.to_s
        end

        nil
      end

      # This reads the guest additions version for a VM.
      def read_guest_additions_version
        output = execute("guestproperty", "get", @uuid, "/VirtualBox/GuestAdd/Version")
        return $1.to_s if output =~ /^Value: (.+?)$/
        return nil
      end

      # This reads the state for the given UUID. The state of the VM
      # will be returned as a symbol.
      def read_state
        output = execute("showvminfo", @uuid, "--machinereadable")
        if output =~ /^name="<inaccessible>"$/
          return :inaccessible
        elsif output =~ /^VMState="(.+?)"$/
          return $1.to_sym
        end

        nil
      end

      # This will read all the used ports for port forwarding by
      # all virtual machines.
      def read_used_ports
        ports = []
        execute("list", "vms").split("\n").each do |line|
          if line =~ /^".+?" \{(.+?)\}$/
            read_forwarded_ports($1.to_s, true).each do |_, _, hostport, _|
              ports << hostport
            end
          end
        end

        ports
      end

      # This sets the MAC address for a network adapter.
      def set_mac_address(mac)
        execute("modifyvm", @uuid, "--macaddress1", mac)
      end

      protected

      # This returns a list of the forwarded ports in the form
      # of `[nic, name, hostport, guestport]`.
      #
      # @return [Array<Array>]
      def read_forwarded_ports(uuid, active_only=false)
        results = []
        current_nic = nil
        execute("showvminfo", uuid, "--machinereadable").split("\n").each do |line|
          # This is how we find the nic that a FP is attached to,
          # since this comes first.
          current_nic = $1.to_i if line =~ /^nic(\d+)=".+?"$/

          # If we care about active VMs only, then we check the state
          # to verify the VM is running.
          if active_only && line =~ /^VMState="(.+?)"$/ && $1.to_s != "running"
            return []
          end

          # Parse out the forwarded port information
          if line =~ /^Forwarding.+?="(.+?),.+?,.*?,(.+?),.*?,(.+?)"$/
            results << [current_nic, $1.to_s, $2.to_i, $3.to_i]
          end
        end

        results
      end

      # This returns the version of VirtualBox that is running.
      #
      # @return [String]
      def read_version
        execute("--version").split("r")[0]
      end

      # Execute the given subcommand for VBoxManage and return the output.
      def execute(*command)
        # TODO: Detect failures and handle them
        r = Subprocess.execute("VBoxManage", *command)
        if r.exit_code != 0
          raise Exception, "FAILURE: #{r.stderr}"
        end
        r.stdout
      end
    end
  end
end