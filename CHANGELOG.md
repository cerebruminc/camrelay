# Changelog

## [0.2.0](https://github.com/cerebruminc/camrelay/compare/v0.1.0...v0.2.0) (2026-10-05)


### Features

* **android:** add single-image emulator backend ([c1523f7](https://github.com/cerebruminc/camrelay/commit/c1523f759dbdf1757c766884fbbac8972a8bb774))
* **android:** separate emulator lifecycle from relay ([114b182](https://github.com/cerebruminc/camrelay/commit/114b182aef271b6da571ff74e36a23d5e5c0676a))
* **android:** support video and fixture switching ([3e74963](https://github.com/cerebruminc/camrelay/commit/3e74963d480802079dcaaec5d4fa421d7c0437c4))
* **expo:** demonstrate frame processor delivery ([065cfa0](https://github.com/cerebruminc/camrelay/commit/065cfa03ab91a3ac53c44f2aa7da5e579bccd9a1))
* init camrelay ([645e958](https://github.com/cerebruminc/camrelay/commit/645e958d4fdfd7840be611ef497142bc36503b17))
* support multiple fixtures without restarting app ([0077480](https://github.com/cerebruminc/camrelay/commit/0077480963968f5a1b72b3ec12ac77731da423e1))


### Bug Fixes

* **android:** show complete camera fixtures ([082d2ae](https://github.com/cerebruminc/camrelay/commit/082d2aef9f271572404330f0b59ebe717157ef0b))
* **ios:** align camera format with delivered frame dimensions ([22cef34](https://github.com/cerebruminc/camrelay/commit/22cef343dfe9ee5a376655a083dd0f6e3d4549ae))
* **ios:** deliver correctly oriented portrait video ([6c4de55](https://github.com/cerebruminc/camrelay/commit/6c4de55987a8267bd7b35b7be49f1c3d9acd0d2c))
* **ios:** preserve video resolution across fixture switches ([c9463b4](https://github.com/cerebruminc/camrelay/commit/c9463b4f124b9804629cac86ad8216e002667d84))
* **ios:** prevent crashes when scanning relayed QR codes ([9b33dbe](https://github.com/cerebruminc/camrelay/commit/9b33dbee4dd1ad4e62d671b62a863b2693841861))
* **ios:** prevent unbounded camera frame buffering ([d7724e5](https://github.com/cerebruminc/camrelay/commit/d7724e5f0d267fad2f73636ebe65d0473cab979b))
* **ios:** prevent VideoToolbox memory exhaustion ([69c2201](https://github.com/cerebruminc/camrelay/commit/69c2201c3fd17e1964d0637d3af6da992e30bef4))


### Documentation

* add CamRelay icon to README ([4b5adc8](https://github.com/cerebruminc/camrelay/commit/4b5adc849b1cd12016c281ce2fac3d398f110aeb))


### Miscellaneous Chores

* add MIT license ([d7a0886](https://github.com/cerebruminc/camrelay/commit/d7a08867bd3b21a8728d2f6b65cda13105e2f830))
* reorganize docs ([4fdd74e](https://github.com/cerebruminc/camrelay/commit/4fdd74e049b982382ab595add713c3b594ce0276))


### Tests

* **android:** add emulator compatibility validation ([1143320](https://github.com/cerebruminc/camrelay/commit/1143320e54bc03d5a6e5272aa01d25ee3761f0e8))


### Continuous Integration

* automate releases with release-please ([c2adde9](https://github.com/cerebruminc/camrelay/commit/c2adde982815770b3db4eaf461cd3933aec2f4a2))
* run iOS integration tests on pull requests ([c1fe8b0](https://github.com/cerebruminc/camrelay/commit/c1fe8b082fbe8c1cdb26091d67d5899a856eed9f))
* run Swift and Expo checks on pull requests ([0f0c79b](https://github.com/cerebruminc/camrelay/commit/0f0c79be13cfc6195e634cbb6ed2344086a4b1bd))
