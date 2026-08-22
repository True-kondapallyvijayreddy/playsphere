/// "1st", "2nd", "3rd", "11th" — the one piece of English that both the
/// house-name templates and the roster line need, in a place neither has to
/// import the other to reach.
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
