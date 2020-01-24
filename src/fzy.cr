module Fzy
  extend self

  VERSION = "0.1.0"

  SCORE_MIN               = -Float32::INFINITY
  SCORE_MAX               = Float32::INFINITY
  SCORE_GAP_LEADING       = -0.005_f32
  SCORE_GAP_TRAILING      = -0.005_f32
  SCORE_GAP_INNER         =  -0.01_f32
  SCORE_MATCH_CONSECUTIVE =    1.0_f32
  SCORE_MATCH_SLASH       =    0.9_f32
  SCORE_MATCH_WORD        =    0.8_f32
  SCORE_MATCH_CAPITAL     =    0.7_f32
  SCORE_MATCH_DOT         =    0.6_f32

  class Match
    include Comparable(Match)
    property positions
    getter value
    getter score

    def initialize(needle : String, @haystack : String)
      # TODO: Unify this to avoid call compute method twite
      @positions = Fzy.positions(needle, haystack)
      @score = Fzy.score(needle, haystack)
      @value = haystack
    end

    def <=>(other)
      other.score <=> @score
    end
  end

  def search(needle : String, haystack : Array(String))
    haystack.select do |hay|
      match?(needle, hay)
    end.map do |hay|
      Match.new(needle, hay)
    end.sort
  end

  def search(needle : String, haystack : PreparedHaystack)
    haystack.filter(needle)
  end

  # Returns true if needle matches haystack
  def match?(needle : String, haystack : String) : Bool
    offset = 0
    needle.each_char do |nch|
      new_offset = haystack.index(nch, offset)
      new_offset = haystack.index(nch.uppercase? ? nch.downcase : nch.upcase, offset) if new_offset.nil?
      return false if new_offset.nil?

      offset = new_offset + 1
    end
    true
  end

  # Finds the score of needle for haystack.
  def score(needle : String, haystack : String) : Float32
    n = needle.size
    m = haystack.size

    # Unreasonably large candidate: return no score
    # If it is a valid match it will still be returned, it will
    # just be ranked below any reasonably sized candidates
    return SCORE_MIN if n.zero? || m.zero? || m > 1024
    # Since this method can only be called with a haystack which
    # matches needle. If the lengths of the strings are equal the
    # strings themselves must also be equal (ignoring case).
    return SCORE_MAX if n === m

    d_table = Array.new(n, [] of Float32)
    m_table = Array.new(n, [] of Float32)
    compute(needle, haystack, d_table, m_table)

    m_table[n - 1][m - 1]
  end

  private def score(needle : String, haystack : String, d_table, m_table) : Float32
  end

  def positions(needle : String, haystack : String) : Array(Int32)
    n = needle.size
    m = haystack.size

    positions = Array.new(n, -1)
    return positions if n.zero? || m.zero? || m > 1024
    if n == m
      return positions.map_with_index! { |_e, i| i }
    end

    d_table = Array.new(n, [] of Float32)
    m_table = Array.new(n, [] of Float32)

    compute(needle, haystack, d_table, m_table)

    # backtrack to find the positions of optimal matching
    match_required = false

    j = m - 1
    (n - 1).downto(0) do |i|
      j.downto(0) do |j|
        # There may be multiple paths which result in
        # the optimal weight.
        #
        # For simplicity, we will pick the first one
        # we encounter, the latest in the candidate
        # string.
        if (d_table[i][j] != Fzy::SCORE_MIN) && (match_required || d_table[i][j] == m_table[i][j])
          # If this score was determined using
          # SCORE_MATCH_CONSECUTIVE, the
          # previous character MUST be a match

          match_required = i > 0 && j > 0 && m_table[i][j] == (d_table[i - 1][j - 1] + Fzy::SCORE_MATCH_CONSECUTIVE)
          positions[i] = j
          j -= 1
          break
        end
      end
    end

    positions
  end

  private def precompute_bonus(haystack) : Array(Float32)
    # Which positions are beginning of words
    m = haystack.size
    match_bonus = Array(Float32).new(m)

    last_ch = '/'

    Array(Float32).new(m) do |i|
      ch = haystack[i]
      match_bonus = if last_ch === '/'
                      SCORE_MATCH_SLASH
                    elsif last_ch === '-' || last_ch === '_' || last_ch === ' '
                      SCORE_MATCH_WORD
                    elsif last_ch === '.'
                      SCORE_MATCH_DOT
                    elsif last_ch.lowercase? && ch.uppercase?
                      SCORE_MATCH_CAPITAL
                    else
                      0_f32
                    end
      last_ch = ch
      match_bonus
    end
  end

  private def compute(needle, haystack, d_table, m_table) : Nil
    n = needle.size
    m = haystack.size

    lower_needle = needle.downcase
    lower_haystack = haystack.downcase

    match_bonus = precompute_bonus(haystack)

    # D[][] Stores the best score for this position ending with a match.
    # M[][] Stores the best possible score at this position.

    prev_score = SCORE_MIN
    n.times do |i|
      d_table[i] = Array.new(m, 0_f32)
      m_table[i] = Array.new(m, 0_f32)

      prev_score = SCORE_MIN
      gap_score = i == n - 1 ? SCORE_GAP_TRAILING : SCORE_GAP_INNER

      m.times do |j|
        if lower_needle[i] == lower_haystack[j]
          score = SCORE_MIN
          if i.zero?
            score = (j * SCORE_GAP_LEADING) + match_bonus[j]
          elsif (j) # i > 0 && j > 0
            score = Math.max(
              m_table[i - 1][j - 1] + match_bonus[j],
              # consecutive match, doesn't stack with match_bonus
              d_table[i - 1][j - 1] + SCORE_MATCH_CONSECUTIVE)
          end
          d_table[i][j] = score
          m_table[i][j] = prev_score = Math.max(score, prev_score + gap_score)
        else
          d_table[i][j] = SCORE_MIN
          m_table[i][j] = prev_score = prev_score + gap_score
        end
      end
    end
  end
end