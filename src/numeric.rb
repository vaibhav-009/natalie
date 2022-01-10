module Numeric
  def coerce(other)
    self.class == other.class ? [other, self] : [Float(other), Float(self)]
  end

  def eql?(other)
    self.class == other.class && self == other
  end

  def -@
    minuend, subtrahend = self.coerce(0)
    minuend - subtrahend
  end

  def +@
    self
  end

  def negative?
    self < 0
  end

  def positive?
    self > 0
  end

  def zero?
    self == 0
  end

  def abs
    self.negative? ? -self : self
  end

  alias magnitude abs

  def abs2
    self * self
  end

  def arg
    self.negative? ? Math::PI : 0
  end

  alias angle arg

  def conj
    self
  end

  alias conjugate conj

  def ceil
    Float(self).ceil
  end

  def floor
    Float(self).floor
  end

  def round
    Float(self).round
  end

  def truncate
    Float(self).truncate
  end

  def clone(freeze: nil)
    raise ArgumentError, "can't unfreeze #{self.class}" if freeze == false
    self
  end

  def dup
    self
  end

  def div(other)
    raise ZeroDivisionError, 'divided by 0' if other.zero?
    (self / other).floor
  end

  def %(other)
    self - other * self.div(other)
  end

  alias modulo %

  def divmod(other)
    [self.div(other), self % other]
  end
end