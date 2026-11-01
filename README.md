# Sinapse para Mac

O Sinapse é um app de tasks para macOS. A interface fica no `sinapse.html` e roda numa janela nativa (WKWebView), com ícone próprio no Dock e notificações do sistema.

## Apresentação



https://github.com/user-attachments/assets/0c6f6312-bdb9-4831-826f-6da8f48139b8





## Requisitos

- macOS 11 ou mais recente
- Ferramentas de Linha de Comando do Xcode (o instalador pede para instalar, se faltar)

## Instalar

```bash
bash instalar.sh
```

O script compila o `main.swift` e instala o Sinapse na pasta Aplicativos.

## Atualizar

Quando houver um `sinapse.html` novo, abra o app e use o menu **Sinapse › Atualizar o Sinapse com um novo arquivo…**. Não é preciso compilar de novo.

## Onde ficam os dados

- Tasks: `~/Library/Application Support/Sinapse/dados.json`
- Backups diários (últimos 60 dias): `~/Library/Application Support/Sinapse/Backups`

O menu **Sinapse › Mostrar a pasta de dados** abre essa pasta. Para levar as tasks de uma versão antiga, use **⋯ › Exportar backup** nela e **⋯ › Importar backup** no app novo.

## Estrutura

| Arquivo | O que é |
| --- | --- |
| `main.swift` | App nativo: janela, armazenamento dos dados e notificações |
| `sinapse.html` | Interface completa do app |
| `instalar.sh` | Compila e instala o app |
| `Info.plist` | Metadados do bundle |
| `AppIcon.icon`, `AppIcon.icns`, `Assets.car` | Ícone do app |
| `docs/apresentacao.mp4` | Vídeo de apresentação |
