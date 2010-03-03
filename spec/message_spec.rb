describe "Donkey::Message" do
  it "raises if a class has no associated tag" do
    new_message_class = Class.new(Donkey::Message)
    lambda { new_message_class.tag }.should raise_error
  end

  it "raises if a tag has no associated class" do
    lambda { Donkey::Message.tag_to_class("fwajelkfjlfla") }.should raise_error
  end

  context ".decode" do
    it "raises DecodeError on bad payload" do
      lambda { Donkey::Message.decode("junk data") }.should raise_error(Donkey::Message::DecodeError)
    end
  end

  context "Message" do
    before(:each) do
      msg_klass = Class.new(Donkey::Message)
      stub(msg_klass).tag { "test_tag" }
      @msg = msg_klass.new("data")
    end

    it "tags data to indicate type" do
      @msg.tagged_data.should be_an(Array)
      @msg.tagged_data[0].should == "test_tag"
      @msg.tagged_data[1].should == "data"
    end

    it "encodes data" do
      mock(@msg).tagged_data { "tagged-data" }
      mock(BERT).encode("tagged-data") { "bert" }
      @msg.encode.should == "bert"
    end
  end
  
  
  context "Call" do
    before(:each) do
      @call = Donkey::Message::Call.new(@data = "data")
    end

    it "has tag" do
      @call.tag.should == "call"
    end
  end

  context "Cast" do
    before(:each) do
      @msg = Donkey::Message::Cast.new(@data="data")
    end

    it "has tag" do
      @msg.tag.should == "cast"
    end
  end
end
