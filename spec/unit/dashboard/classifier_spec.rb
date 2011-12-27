require 'spec_helper'
require 'puppet/dashboard/classifier'
describe Puppet::Dashboard::Classifier do

  let :one_element_list do
    [{"name"=>"first", "id"=>"1" }]
  end

  let :http_mock do
    mock('Net::Http')
  end

  let :connection_options do
    {
      :enc_server => 'puppet',
      :enc_port => 443,
      :enc_auth_user => 'dan',
      :enc_auth_passwd => 'pass',
      :enc_ssl => true
    }
  end

  let :default_connection do
    Puppet::Dashboard::Classifier.connection(connection_options)
  end

  describe '#self.to_array' do
    it 'should not modify an array' do
      Puppet::Dashboard::Classifier.to_array(['1','2','3']).should == ['1','2','3']
    end
    it 'should be able to convert a comma delim list into an array' do
      Puppet::Dashboard::Classifier.to_array('1,2,3').should == ['1','2','3']
    end
  end

  describe 'with ssl and authentication' do

    def expect_list(type, label)
      Puppet::Dashboard::Classifier.expects(:http_request).with(
          http_mock,
          "/#{label}.json",
          connection_options,
          "Listing #{type}"
      )
    end

    def expect_create(type, label, name, data)
      Puppet::Dashboard::Classifier.expects(:http_request).with(
        http_mock,
        "/#{label}.json",
        connection_options,
        "Creating #{type} #{name}",
        '201',
        data
      )
    end

    before :all do
      # stub http connection
      Puppet::Network::HttpPool.expects(:http_instance).with(
        connection_options[:enc_server],
        connection_options[:enc_port]
      ).returns(http_mock)
      http_mock.expects(:use_ssl=).with(true)
      http_mock.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    end

    {'node' => 'nodes', 'group' => 'node_groups'}.each do |k,v|
      it "should be able to find existing #{k}" do
    # what does list return?
        expect_list("#{k}s", v).returns(one_element_list)
        default_connection.send("find_#{k}".to_sym, 'first').should == one_element_list.first
      end
    end
    it 'should be able to create a class' do
      expect_create(
        'class',
        'node_classes',
        'foo',
        {'node_class' => {'name' => 'foo'}}
      ).returns('result')
      default_connection.create_class('foo').should == 'result'
    end
    describe '#create_node' do
      describe 'when the node already exists' do
        before :all do
          expect_list('nodes', 'nodes').returns(one_element_list)
        end
        it 'should fail if the node exists' do
          default_connection.create_node('first', nil, nil, nil).should == {:status => "Node first already exists"}
        end
      end
      describe 'when creating a node that does not exist' do
        before :each do
          expect_list('nodes', 'nodes').returns []
        end
        it 'should be able to create nodes without any additional data' do
          expect_create(
            'node',
            'nodes',
            'first',
            {'node' => {'name' => 'first', 'assigned_node_group_ids' => [], 'parameter_attributes' => [], 'assigned_node_class_ids' => []}}
          ).returns('result')
          default_connection.create_node('first', nil, nil, nil).should == 'result'
        end
        it 'should create classes that do not exists' do
          expect_list('classes', 'node_classes').returns([])
          expect_create(
            'class',
            'node_classes',
            'one',
            { 'node_class' => { 'name' => 'one' } }
          ).returns({'name' => 'one', 'id' => 2})
          expect_create(
            'node',
            'nodes',
            'first',
            {'node' => {'name' => 'first', 'assigned_node_group_ids' => [], 'parameter_attributes' => [], 'assigned_node_class_ids' => [2]}}
          ).returns('result')
          default_connection.create_node('first', ['one'], nil, nil).should == 'result'
        end
        it 'should not create existing classes' do
          expect_list('classes', 'node_classes').returns([
            {'name' => 'one', 'id' => '1'},
            {'name' => 'two', 'id' => '2'},
          ])
          expect_create(
            'node',
            'nodes',
            'first',
            # I am not sure if this test will always pass
            # will the array always be in this order?
            # this test is based on an assumed order of
            # hash iteration and will break
            {'node' => {'name' => 'first', 'assigned_node_group_ids' => [], 'parameter_attributes' => [], 'assigned_node_class_ids' => ['2', '1']}}
          ).returns('result')
          default_connection.create_node('first', ['one', 'two'], nil, nil).should == 'result'
        end
        it 'should be able to specify parameters' do
          expect_create(
            'node',
            'nodes',
            'node_name',
            {'node' => {'name' => 'node_name', 'assigned_node_group_ids' => [], 'parameter_attributes' => [{'value' => 'bar', 'key' => 'foo'}], 'assigned_node_class_ids' => []}}
          ).returns('result')
          default_connection.create_node('node_name', nil, {'foo' => 'bar'}, nil).should == 'result'
        end
        it 'should be able to add existing groups' do
          expect_list('groups', 'node_groups').returns([
            {'name' => 'group1', 'id' => '1'},
          ])
          expect_create(
            'node',
            'nodes',
            'node_name',
            {'node' => {'name' => 'node_name', 'assigned_node_group_ids' => ['1'], 'parameter_attributes' => [], 'assigned_node_class_ids' => []}}
          ).returns('result')
          default_connection.create_node('node_name', nil, nil, ['group1']).should == 'result'
        end
        it 'should fail if a specified group does not exist' do
          expect_list('groups', 'node_groups').returns([
            {'name' => 'group1', 'id' => '1'},
          ])
          default_connection.create_node('node_name', nil, nil, ['group2']).should == {:status => "Parent Group group2 for node node_name does not exist"}
        end
      end
    end
    describe '#create_group' do

    end
  end

end
