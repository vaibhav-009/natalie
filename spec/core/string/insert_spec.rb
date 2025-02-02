# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#insert with index, other" do
  it "inserts other before the character at the given index" do
    "abcd".insert(0, 'X').should == "Xabcd"
    "abcd".insert(3, 'X').should == "abcXd"
    "abcd".insert(4, 'X').should == "abcdX"
  end

  it "modifies self in place" do
    a = "abcd"
    a.insert(4, 'X').should == "abcdX"
    a.should == "abcdX"
  end

  it "inserts after the given character on an negative count" do
    "abcd".insert(-5, 'X').should == "Xabcd"
    "abcd".insert(-3, 'X').should == "abXcd"
    "abcd".insert(-1, 'X').should == "abcdX"
  end

  it "raises an IndexError if the index is beyond string" do
    -> { "abcd".insert(5, 'X')  }.should raise_error(IndexError)
    -> { "abcd".insert(-6, 'X') }.should raise_error(IndexError)
  end

  it "converts index to an integer using to_int" do
    other = mock('-3')
    other.should_receive(:to_int).and_return(-3)

    "abcd".insert(other, "XYZ").should == "abXYZcd"
  end

  it "converts other to a string using to_str" do
    other = mock('XYZ')
    other.should_receive(:to_str).and_return("XYZ")

    "abcd".insert(-3, other).should == "abXYZcd"
  end

  it "raises a TypeError if other can't be converted to string" do
    -> { "abcd".insert(-6, Object.new)}.should raise_error(TypeError)
    -> { "abcd".insert(-6, [])        }.should raise_error(TypeError)
    -> { "abcd".insert(-6, mock('x')) }.should raise_error(TypeError)
  end

  it "raises a FrozenError if self is frozen" do
    str = "abcd".freeze
    -> { str.insert(4, '')  }.should raise_error(FrozenError)
    -> { str.insert(4, 'X') }.should raise_error(FrozenError)
  end

  it "inserts a character into a multibyte encoded string" do
    "ありがとう".insert(1, 'ü').should == "あüりがとう"
  end

  xit "returns a String in the compatible encoding" do
    str = "".force_encoding(Encoding::US_ASCII)
    str.insert(0, "ありがとう")
    str.encoding.should == Encoding::UTF_8
  end

  # NATFIXME: Implement multibyte characters and Encoding::EUC_JP
  xit "raises an Encoding::CompatibilityError if the encodings are incompatible" do
    pat = "ア".encode Encoding::EUC_JP
    -> do
      "あれ".insert 0, pat
    end.should raise_error(Encoding::CompatibilityError)
  end

  it "should not call subclassed string methods" do
    cls = Class.new(String) do
      def replace(arg)
        raise "should not call replace"
      end
    end
    cls.new("abcd").insert(0, 'X').should == "Xabcd"
  end
end
