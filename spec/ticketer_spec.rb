require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Ticketer" do
  before do
    @ticketer = Donkey::Ticketer.new
  end
  
  it "produces a unique ticket" do
    # well... kinda lame way to test it.
    Set.new(10.times.map { @ticketer.next }).should have(10).tickets
  end
end
