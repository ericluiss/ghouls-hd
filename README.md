# Ghouls 'n Ghosts HD (Godot 4)

Projeto Godot que roda a ROM original do Ghouls 'n Ghosts (Mega Drive / Genesis) e preenche a tela de 1920x1080 com o cenário.
A emulação é feita pelo core libretro [Genesis Plus GX Wide](https://github.com/libretro/Genesis-Plus-GX-Wide),
e o Godot cuida da janela, da escala, do áudio, dos controles e do menu.

A ROM **não** faz parte do projeto nem do git (veja `.gitignore`). Você usa a sua própria cópia.

## Como funciona

```
ROM (.md/.zip) ──> core Genesis Plus GX Wide (.dll/.so/.dylib)
                        │  quadros 400x224, áudio 44,1 kHz, controle
                        ▼
      GDExtension libretro_host (C++, classe LibretroCore)
                        ▼
      main.gd: textura -> shader de escala nítida -> tela 1920x1080
```

- `extension/src/` — frontend libretro mínimo em C++ (godot-cpp). Carrega o core em tempo de execução,
  converte os quadros para uma `ImageTexture`, entrega o áudio e recebe os botões.
- `game/` — o projeto Godot (abra `game/project.godot`).
  - `main.gd` — procura core e ROM, roda os quadros no ritmo certo (sincronizado pelo áudio), controles, save states.
  - `shaders/retro_screen.gdshader` — escala "sharp bilinear": pixels nítidos mesmo em escala não inteira.

### Sobre a resolução

O Mega Drive gera 320x224 pixels. O core Wide desenha 10 colunas extras de 8 pixels, chegando a 400x224,
praticamente 16:9. Nada é esticado: o que aparece a mais é cenário de verdade. O projeto tem três modos (F1):

| Modo | Tamanho na tela | Observação |
|---|---|---|
| Preencher a tela (padrão) | 1920x1080 | Sem bordas |
| Pixels quadrados | ~1920x1075 | Cada pixel do console é quadrado |
| Escala inteira 4x | 1600x896 | Pixel perfect, com bordas pretas |

O jogo foi feito para uma tela de 320 pixels e só carregava cenário até esse limite. O `main.gd` ajusta a rotina
de carregamento numa cópia da ROM para cobrir os 400 pixels, e faz a câmera parar 8 pixels antes do início do mapa,
para não aparecer faixa preta à esquerda. Restam duas limitações: inimigos podem surgir ou sumir perto das laterais,
e, no fim do mapa de cada fase, a borda direita ainda pode mostrar uma faixa sem cenário.

Com o core comum (`genesis_plus_gx_libretro`) o jogo continua funcionando, mas em 4:3 com bordas pretas.

"HD" aqui significa saída nativa em Full HD, limpa e sem borrão. A arte continua sendo a original do Mega Drive;
a remasterização de sprites e cenários é a próxima etapa.

### Versão e dificuldade

O menu aparece ao abrir o jogo, e Esc volta para ele durante a partida. Escolha a versão americana (Ghouls'n Ghosts)
ou a japonesa (Daimakaimura); trocar de versão reinicia o jogo. A ROM é a mesma: o que muda é a região informada ao
console. A escolha fica salva, e cada versão tem o seu próprio estado salvo.

A dificuldade começa em PROFESSIONAL, e ainda pode ser trocada em OPTION na tela do jogo. Esse valor inicial também é
alterado na cópia da ROM em `user://cache`; o seu arquivo original não é modificado.

## Preparação

Requisitos: Godot **4.3 ou mais novo**, Git, Python 3 e um compilador C++
(Windows: Visual Studio Build Tools com "Desenvolvimento para desktop com C++"; Linux: gcc; macOS: Xcode Command Line Tools).

**Windows** (PowerShell, na pasta do projeto):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

**Linux / macOS**:

```bash
./scripts/setup.sh              # baixa o core pronto do buildbot do libretro
./scripts/setup.sh --build-core # ou compila o Genesis Plus GX Wide a partir do código-fonte
```

O script compila a extensão em `game/addons/libretro_host/bin/` e coloca o core em `game/cores/`.

Depois:

1. Copie a ROM para `game/roms/` (pode ser o `.zip` mesmo).
2. Abra `game/project.godot` no Godot e aperte F5.

Se não houver ROM na pasta, o jogo abre um seletor de arquivo; também dá para arrastar a ROM para a janela.
Pela linha de comando: `godot --path game -- --rom=/caminho/para/rom.md`.

## Controles

| Mega Drive | Teclado | Controle (Xbox) |
|---|---|---|
| Direcional | Setas | D-pad / analógico esquerdo |
| A | A ou Z | X |
| B | S ou X | A |
| C | D ou C | B |
| Start | Enter | Start |

| Atalho | Tecla |
|---|---|
| Menu (versão) | Esc / botão Guide |
| Modo de tela | F1 |
| Scanlines liga/desliga | F2 |
| Reset | F3 |
| Abrir outra ROM | F4 |
| Salvar / carregar estado | F5 / F8 |
| Tela cheia | F11 |
| Avanço rápido (segurar) | Tab / RB |

Os controles podem ser trocados no Input Map do projeto (Projeto > Configurações > Mapa de entrada): ações
`md_*` e `emu_*` definidas lá têm prioridade sobre as padrão do `main.gd`.

## Exportando

Ao exportar o jogo, coloque a pasta `cores/` (com o core da plataforma) **ao lado do executável**, e,
se quiser, uma pasta `roms/` também. Bibliotecas nativas não podem ficar dentro do `.pck`.

## Licenças

- Código deste projeto: livre para você usar e modificar.
- `extension/include/libretro.h`: licença MIT (RetroArch team).
- Genesis Plus GX Wide: licença própria, não comercial. Ele é baixado à parte e não vem neste repositório.
- Ghouls 'n Ghosts © Capcom. Use apenas uma ROM de um cartucho seu.
