pub fn known_names(output: &str) -> (Vec<String>, bool) {
    let plain = strip_ansi(output);
    let mut names = Vec::new();
    let mut has_unmanaged = false;
    for line in plain.lines().filter(|line| line.contains("| Hardware:")) {
        let Some(end) = line.find(']') else { continue };
        let Some(start) = line[..end].rfind('[') else {
            continue;
        };
        let name = line[start + 1..end].trim();
        if name == "?" {
            has_unmanaged = true;
        } else if valid_name(name) && !names.iter().any(|known| known == name) {
            names.push(name.to_owned());
        }
    }
    (names, has_unmanaged)
}

fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
}

fn strip_ansi(input: &str) -> String {
    let mut plain = String::new();
    let mut escaped = false;
    for character in input.chars() {
        if escaped {
            if character.is_ascii_alphabetic() {
                escaped = false;
            }
        } else if character == '\u{1b}' {
            escaped = true;
        } else {
            plain.push(character);
        }
    }
    plain
}
