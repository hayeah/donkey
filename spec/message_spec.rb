require 'spec/spec_helper'

describe "Donkey::Message" do
  it "raises if a class has no associated tag" do
    new_message_class = Class.new(Donkey::Message)
    lambda { new_message_class.tag }.should raise_error
  end

  it "raises if a tag has no associated class" do
    lambda { Donkey::Message.tag_to_class(2313) }.should raise_error(Donkey::Message::DecodeError)
  end

  context ".decode" do
    it "raises DecodeError on bad payload" do
      lambda { Donkey::Message.decode("junk data") }.should raise_error(Donkey::Message::DecodeError)
    end
  end
  
  context "Call" do
    let(:msg) {
      Donkey::Message::Call.new(@data = "data")
    }

    subject { msg }
    
    it "has tag" do
      msg.tag.should == ?0
    end

    it "encodes" do
      msg.encode.should == "0#{@data}"
    end
  end

  describe "Cast" do
    let(:msg) {
      Donkey::Message::Cast.new(@data="data")
    }

    subject { msg }
    
    it "has tag" do
      msg.tag.should == ?1
    end

    it "encodes" do
      msg.encode.should == "1#{@data}"
    end
  end

  describe "Back" do
    let(:msg) {
      Donkey::Message::Back.new(@data="data")
    }

    subject { msg }
    
    it "has tag" do
      msg.tag.should == ?2
    end

    it "encodes" do
      msg.encode.should == "2#{@data}"
    end

    def decode(payload)
      Donkey::Message.decode(payload)
    end

    it "decodes" do
      msg = Donkey::Message.decode("2data")
      msg.should be_a(Donkey::Message::Back)
      msg.data.should == "data"
    end
  end
end
