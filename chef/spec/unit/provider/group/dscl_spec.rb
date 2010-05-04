#
# Author:: Dreamcat4 (<dreamcat4@gmail.com>)
# Copyright:: Copyright (c) 2009 OpsCode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Group::Dscl, "dscl" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @status = mock("Process::Status", :null_object => true, :exitstatus => 0) 
    @pid = mock("PID", :null_object => true)
    @stdin = mock("STDIN", :null_object => true)
    @stdout = mock("STDOUT", :null_object => true)
    @stderr = mock("STDERR", :null_object => true)
    @stdout.stub!(:each).and_yield("\n")
    @stderr.stub!(:each).and_yield("")
    @provider.stub!(:popen4).and_yield(@pid,@stdin,@stdout,@stderr).and_return(@status)
  end
  
  it "should run popen4 with the supplied array of arguments appended to the dscl command" do
    @provider.should_receive(:popen4).with("dscl . -cmd /Path arg1 arg2")
    @provider.dscl("cmd", "/Path", "arg1", "arg2")
  end

  it "should return an array of four elements - cmd, status, stdout, stderr" do
    dscl_retval = @provider.dscl("cmd /Path args")
    dscl_retval.should be_a_kind_of(Array)
    dscl_retval.should == ["dscl . -cmd /Path args",@status,"\n",""]
  end
end

describe Chef::Provider::Group::Dscl, "safe_dscl" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @status = mock("Process::Status", :null_object => true, :exitstatus => 0)
    @provider.stub!(:dscl).and_return(["cmd", @status, "stdout", "stderr"])
  end
 
  it "should run dscl with the supplied cmd /Path args" do
    @provider.should_receive(:dscl).with("cmd /Path args")
    @provider.safe_dscl("cmd /Path args")
  end

  describe "with the dscl command returning a non zero exit status for a delete" do
    before do
      @status = mock("Process::Status", :null_object => true, :exitstatus => 1)
      @provider.stub!(:dscl).and_return(["cmd", @status, "stdout", "stderr"])
    end

    it "should return an empty string of standard output for a delete" do
      safe_dscl_retval = @provider.safe_dscl("delete /Path args")
      safe_dscl_retval.should be_a_kind_of(String)
      safe_dscl_retval.should == ""
    end

    it "should raise an exception for any other command" do
      lambda { @provider.safe_dscl("cmd /Path arguments") }.should raise_error(Chef::Exceptions::Group)
    end
  end

  describe "with the dscl command returning no such key" do
    before do
      # @status = mock("Process::Status", :null_object => true, :exitstatus => 0)
      @provider.stub!(:dscl).and_return(["cmd", @status, "No such key: ", "stderr"])
    end

    it "should raise an exception" do
      lambda { @provider.safe_dscl("cmd /Path arguments") }.should raise_error(Chef::Exceptions::Group)
    end
  end
 
  describe "with the dscl command returning a zero exit status" do
    it "should return the third array element, the string of standard output" do
      safe_dscl_retval = @provider.safe_dscl("cmd /Path args")
      safe_dscl_retval.should be_a_kind_of(String)
      safe_dscl_retval.should == "stdout"
    end
  end
end

describe Chef::Provider::Group::Dscl, "get_free_gid" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.stub!(:safe_dscl).and_return("\naj      200\njt      201\n")
  end
  
  it "should run safe_dscl with list /Groups gid" do
    @provider.should_receive(:safe_dscl).with("list /Groups gid")
    @provider.get_free_gid
  end

  it "should return the first unused gid number on or above 200" do
    @provider.get_free_gid.should equal(202)
  end
  
  it "should raise an exception when the search limit is exhausted" do
    search_limit = 1
    lambda { @provider.get_free_gid(search_limit) }.should raise_error(RuntimeError)
  end
end

describe Chef::Provider::Group::Dscl, "gid_used?" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.stub!(:safe_dscl).and_return("\naj      500\n")
  end

  it "should run safe_dscl with list /Groups gid" do
    @provider.should_receive(:safe_dscl).with("list /Groups gid")
    @provider.gid_used?(500)
  end
  
  it "should return true for a used gid number" do
    @provider.gid_used?(500).should be_true
  end

  it "should return false for an unused gid number" do
    @provider.gid_used?(501).should be_false
  end

  it "should return false if not given any valid gid number" do
    @provider.gid_used?(nil).should be_false
  end
end

describe Chef::Provider::Group::Dscl, "set_gid" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :gid => 50,
      :members => [ "root", "aj"]
    )
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.stub!(:get_free_gid).and_return(501)
    @provider.stub!(:gid_used?).and_return(false)
    @provider.stub!(:safe_dscl).and_return(true)
  end

  describe "with the new resource and a gid number which is already in use" do
    before do
      @provider.stub!(:gid_used?).and_return(true)
    end

    it "should raise an exception if the new resources gid is already in use" do
      lambda { @provider.set_gid }.should raise_error(Chef::Exceptions::Group)
    end
  end
  
  describe "with no gid number for the new resources" do
    before do
      @new_resource = mock("Chef::Resource::Group",
        :null_object => true,
        :group_name => "aj",
        :gid => nil,
        :members => [ "root", "aj"]
      )
      @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
      @provider.stub!(:get_free_gid).and_return(501)
      @provider.stub!(:gid_used?).and_return(false)
      @provider.stub!(:safe_dscl).and_return(true)
    end

    it "should run get_free_gid and return a valid, unused gid number" do
      @provider.should_receive(:get_free_gid).and_return(501)
      @provider.set_gid
    end
  end

  describe "with blank gid number for the new resources" do
    before do
      @new_resource = mock("Chef::Resource::Group",
        :null_object => true,
        :group_name => "aj",
        :gid => "",
        :members => [ "root", "aj"]
      )
      @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
      @provider.stub!(:get_free_gid).and_return(501)
      @provider.stub!(:gid_used?).and_return(false)
      @provider.stub!(:safe_dscl).and_return(true)
    end

    it "should run get_free_gid and return a valid, unused gid number" do
      @provider.should_receive(:get_free_gid).and_return(501)
      @provider.set_gid
    end
  end

  describe "with a valid gid number which is not already in use" do
    it "should run safe_dscl with create /Groups/group PrimaryGroupID gid" do
      @provider.should_receive(:safe_dscl).with("create /Groups/aj PrimaryGroupID 50").and_return(true)
      @provider.set_gid
    end
  end
end

describe Chef::Provider::Group::Dscl, "set_members" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :members => [ "all", "your", "base" ]
    )
    @current_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :members => [ "all", "your", "base" ]
    )
    @new_resource.stub!(:to_s).and_return("group[aj]")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.current_resource = @current_resource
    @provider.stub!(:safe_dscl).and_return(true)
  end

  describe "with existing members in the current resource and append set to false in the new resource" do
    before do
      @new_resource.stub!(:members).and_return([])
      @new_resource.stub!(:append).and_return(false)
      @current_resource.stub!(:members).and_return(["all", "your", "base"])
    end

    it "should log an appropriate message" do
      Chef::Log.should_receive(:debug).with("group[aj]: removing group members all your base")
      @provider.set_members
    end

    it "should run safe_dscl with create /Groups/group GroupMembers to clear the Group's GUID list" do
      @provider.should_receive(:safe_dscl).with("create /Groups/aj GroupMembers ''").and_return(true)
      @provider.set_members
    end

    it "should run safe_dscl with create /Groups/group GroupMembership to clear the Group's UID list" do
      @provider.should_receive(:safe_dscl).with("create /Groups/aj GroupMembership ''").and_return(true)
      @provider.set_members
    end
  end

  describe "with supplied members in the new resource" do
    before do
      @new_resource.stub!(:members).and_return(["all", "your", "base"])
      @current_resource.stub!(:members).and_return([])
    end

    it "should log an appropriate debug message" do
      Chef::Log.should_receive(:debug).with("group[aj]: setting group members all, your, base")
      @provider.set_members
    end

    it "should run safe_dscl with append /Groups/group GroupMembership and group members all, your, base" do
      @provider.should_receive(:safe_dscl).with("append /Groups/aj GroupMembership all your base").and_return(true)
      @provider.set_members
    end
  end
  
  describe "with no members in the new resource" do
    before do
      @new_resource.stub!(:members).and_return([])
    end

    it "should not call safe_dscl" do
      @provider.should_not_receive(:safe_dscl)
      @provider.set_members
    end
  end
end

describe Chef::Provider::Group::Dscl, "load_current_resource" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    File.stub!(:exists?).and_return(false)
  end

  it "should raise an error if the required binary /usr/bin/dscl doesn't exist" do
    File.should_receive(:exists?).with("/usr/bin/dscl").and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Group)
  end

  it "shouldn't raise an error if /usr/bin/dscl exists" do
    File.stub!(:exists?).and_return(true)
    lambda { @provider.load_current_resource }.should_not raise_error(Chef::Exceptions::Group)
  end
end

describe Chef::Provider::Group::Dscl, "create_group" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true)
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.stub!(:manage_group).and_return(true)
  end

  it "should run manage_group with manage=false to create all the group attributes" do
    @provider.should_receive(:manage_group).with(false).and_return(true)
    @provider.create_group
  end
end

describe Chef::Provider::Group::Dscl, "manage_group" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :gid => 50,
      :members => [ "root", "aj"]
    )
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @current_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :members => [ "all", "your", "base" ]
    )
    @provider.current_resource = @current_resource
    @provider.stub!(:safe_dscl).and_return(true)
    @provider.stub!(:set_gid).and_return(true)
    @provider.stub!(:set_members).and_return(true)
  end

  fields = [:group_name,:gid,:members]
  fields.each do |field|
    it "should check for differences in #{field.to_s} between the current and new resources" do
        @new_resource.should_receive(field)
        @current_resource.should_receive(field)
        @provider.manage_group
    end

    it "should manage the #{field} if it changed and the new resources #{field} is not null" do
      @current_resource.stub!(field).and_return("oldval")
      @new_resource.stub!(field).and_return("newval")
      @current_resource.should_receive(field).once
      @new_resource.should_receive(field).twice
      @provider.manage_group
    end
  end

  describe "with manage set to false" do
    before do
      @node = mock("Chef::Node", :null_object => true)
      @new_resource = mock("Chef::Resource::Group",
        :null_object => true,
        :group_name => "aj",
        :gid => 50,
        :members => [ "root", "aj"]
      )
      @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
      @current_resource = mock("Chef::Resource::Group",
        :null_object => true,
        :group_name => "aj",
        :members => [ "all", "your", "base" ]
      )
      @provider.current_resource = @current_resource
      @provider.stub!(:gid_used?).and_return(false)
      @provider.stub!(:safe_dscl).and_return(true)
      @provider.stub!(:set_gid).and_return(true)
      @provider.stub!(:set_members).and_return(true)
      @provider.stub!(:get_free_gid).and_return(501)
    end

    it "should run safe_dscl with create /Groups/group and with the new resources group name" do
      @provider.should_receive(:safe_dscl).with("create /Groups/aj").and_return(true)
      @provider.manage_group(false)
    end

    it "should run safe_dscl with create /Groups/group Password * to set the groups password field" do
      @provider.should_receive(:safe_dscl).with("create /Groups/aj").and_return(true)
      @provider.manage_group(false)
    end

    it "should run set_gid to set the gid number" do
      @provider.should_receive(:set_gid).and_return(true)
      @provider.manage_group(false)
    end

    it "should run set_members to set any group memberships" do
      @provider.should_receive(:set_members).and_return(true)
      @provider.manage_group(false)
    end
  end
  
end

describe Chef::Provider::Group::Dscl, "remove_group" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj"
    )
    @provider = Chef::Provider::Group::Dscl.new(@node, @new_resource)
    @provider.stub!(:safe_dscl).and_return(true)
  end
  
  it "should run safe_dscl with delete /Groups/group and with the new resources group name" do
    @provider.should_receive(:safe_dscl).with("delete /Groups/aj").and_return(true)
    @provider.remove_group
  end
end
