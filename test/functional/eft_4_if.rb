
#
# Testing Ruote (OpenWFEru)
#
# John Mettraux at openwfe.org
#
# Sun Jan 25 15:36:25 JST 2009
#

require File.dirname(__FILE__) + '/base'


class EftIfTest < Test::Unit::TestCase
  include FunctionalBase

  def test_if_then

    pdef = OpenWFE.process_definition :name => 'test' do
      _if do
        equals :value => 'a', :other_value => 'a'
        _print 'ok'
      end
    end

    assert_trace(pdef, 'ok')
  end

  def test_if_else

    pdef = OpenWFE.process_definition :name => 'test' do
      _if do
        equals :value => 'a', :other_value => 'b'
        _print 'ok'
      end
    end

    assert_trace(pdef, '')
  end

  def test_if_not_else

    pdef = OpenWFE.process_definition :name => 'test' do
      _if do
        equals :value => 'a', :other_value => 'a'
        _print 'ok'
        _print 'nok'
      end
    end

    assert_trace(pdef, 'ok')
  end

  def test_if_not_then

    pdef = OpenWFE.process_definition :name => 'test' do
      _if do
        equals :value => 'a', :other_value => 'b'
        _print 'nok'
        _print 'ok'
      end
    end

    assert_trace(pdef, 'ok')
  end

  def test_if_misc

    assert_trace(%{
<process-definition name="test">
  <sequence>
    <if test="3 > 2">
      <print>ok0</print>
    </if>
    <if test="3 > a">
      <print>bad</print>
      <print>ok1</print>
    </if>
    <if test="3>a">
      <print>bad</print>
      <print>ok2</print>
    </if>
    <if test="3 &gt; 2">
      <print>ok3</print>
      <print>bad</print>
    </if>
    <if test="1 &lt; 2.0">
      <print>ok4</print>
      <print>bad</print>
    </if>
  </sequence>
</process-definition>
      },
      (0..4).collect { |i| "ok#{i}" }.join("\n"))
  end
end

