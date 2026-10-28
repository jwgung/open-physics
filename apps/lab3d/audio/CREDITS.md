# 소리 출처와 라이선스

앱의 효과음과 배경 음악은 모두 **CC0 1.0**(퍼블릭 도메인 헌정, <https://creativecommons.org/publicdomain/zero/1.0/>)이다. 출처 표기 의무는 없지만 여기에 남긴다. 2026-10-28에 받았고, 각 팩 안의 `License.txt`에서 CC0를 확인했다. 효과음은 원본 파일을 그대로 복사했다(파일 이름도 팩의 것). 어느 사건에 어느 소리를 쓰는지는 `scripts/core/sound_board.gd`의 `SFX` 표가 정한다.

## 효과음 — Kenney (www.kenney.nl)

| 파일(`audio/sfx/`) | 팩 | 받은 곳 | 쓰는 곳(`SoundBoard` id) |
|---|---|---|---|
| `drop_002.ogg` | Interface Sounds 1.0 | <https://kenney.nl/assets/interface-sounds> | `tap` 단추 (2026-10-28 사용자가 후보 중 고름) |
| `select_002.ogg` | Interface Sounds 1.0 | 위와 같음 | `pick` 그림 단추(조건, 두기두기 질문의 답) |
| `confirmation_001.ogg` | Interface Sounds 1.0 | 위와 같음 | `spot` 지도에서 장소 누르기 |
| `drop_003.ogg` | Interface Sounds 1.0 | 위와 같음 | `splash` 통이 물에 퐁당 |
| `question_002.ogg` | Interface Sounds 1.0 | 위와 같음 | `question` 두기두기가 물음 |
| `card-slide-1.ogg` | Casino Audio 1.1 | <https://kenney.nl/assets/casino-audio> | `whoosh` 화면 바뀜 |
| `impactSoft_medium_000.ogg` | Impact Sounds 1.0 | <https://kenney.nl/assets/impact-sounds> | `hop` 지도에서 빵고양이 깡충 |
| `impactSoft_heavy_000.ogg` | Impact Sounds 1.0 | 위와 같음 | `land` 땅에 떨어짐·부딪힘 |
| `impactGeneric_light_000.ogg` | Impact Sounds 1.0 | 위와 같음 | `bump` 두 공이 부딪힘 |
| `impactWood_light_002.ogg` | Impact Sounds 1.0 | 위와 같음 | `stop` 상자가 멈춤·끝에 닿음, 짐이 꼭대기 |
| `impactWood_heavy_000.ogg` | Impact Sounds 1.0 | 위와 같음 | `stamp` 도장 쾅 |
| `phaseJump1.ogg` | Digital Audio | <https://kenney.nl/assets/digital-audio> | `launch` 놓기·던지기·쏘기·밀기 시작 |
| `pepSound1.ogg` | Digital Audio | 위와 같음 | `spring` 용수철 공을 놓음(보잉) |
| `jingles_PIZZI02.ogg` | Music Jingles (Pizzicato jingles) | <https://kenney.nl/assets/music-jingles> | `fanfare` 다 깼을 때(색종이와 함께) |
| `jingles_PIZZI10.ogg` | Music Jingles (Pizzicato jingles) | 위와 같음 | `flag` 지도 깃발이 솟음 |
| `impactGlass_light_000.ogg` | Impact Sounds 1.0 | <https://kenney.nl/assets/impact-sounds> | `star_break` 이야기: 길잡이 별이 깨짐 (2026-10-28) |
| `glass_002.ogg` | Interface Sounds 1.0 | <https://kenney.nl/assets/interface-sounds> | `glint` 이야기: 별 조각이 나타남·떨어짐·전망대에 도착 |
| `maximize_004.ogg` | Interface Sounds 1.0 | 위와 같음 | `piece_fly` 이야기: 조각이 날아감, 별이 하늘로 오름 |
| `jingles_STEEL00.ogg` | Music Jingles (Steel jingles) | <https://kenney.nl/assets/music-jingles> | `finale` 이야기: 별이 하늘에 돌아감 |

팩의 `License.txt`: "License: (Creative Commons Zero, CC0) http://creativecommons.org/publicdomain/zero/1.0/ … This content is free to use in personal, educational and commercial projects."(Interface Sounds, Impact Sounds), "License (Creative Commons Zero, CC0) … You may use these assets in personal and commercial projects."(Digital Audio, Music Jingles, Casino Audio).

## 배경 음악 — Children's March Theme, Cleyton Kauffman (OpenGameArt: Snabisch)

2026-10-28 사용자가 "더 귀엽고 통통 튀는 곡"으로 후보 6곡을 들어 보고 골랐다(앞선 곡 Happy Clappy Loop을 바꿈).

| 파일 | 원본 | 받은 곳 | 라이선스 |
|---|---|---|---|
| `audio/music/childrens_march.ogg` | `Children's March Theme.wav`(44.1 kHz 스테레오 16비트, 64.0초) | <https://opengameart.org/content/childrens-march-theme> (OpenGameArt) | CC0(페이지의 License(s) 항목이 CC0 하나, 묶음 안 readme.txt "License: Creative Commons Zero (CC0)") |

readme.txt의 표시 요청: "Music by Cleyton Kauffman - https://soundcloud.com/cleytonkauffman". CC0라 의무는 아니지만 여기 남긴다.

바꾼 것: 이음매의 딸깍 소리를 막으려고 처음과 끝 5 ms만 페이드했다(64.0초 그대로, 곡이 끝까지 같은 세기라 박자대로 이어진다). Vorbis q2(약 90 kbps, 716 KB)로 인코딩했다. 반복은 Godot import 설정 `loop=true`(`childrens_march.ogg.import`)가 한다.
