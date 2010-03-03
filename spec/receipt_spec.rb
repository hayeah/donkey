require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Receipt" do
  before do
    @donkey = Object.new
    @key = Object.new
    @receipt = Donkey::Receipt.new(@donkey,@key)
  end

  it "waits" do
    mock(@donkey).wait(@receipt).yields
    m = mock!.call.subject
    @receipt.wait { m.call }
  end
end
