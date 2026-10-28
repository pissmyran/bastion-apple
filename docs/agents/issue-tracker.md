# Issues

GitHub Issues i `pissmyran/bastion_apple` är repots ärendehantering.

## Arbetssätt

- Läs hela ärendet före arbete: text, etiketter, kommentarer och kopplade pull requests.
- Ett ärende ska beskriva ett sammanhållet problem, med acceptanskriterier och hinder i texten.
- Beslut som ska bestå skrivs in i dokumentationen, inte bara i en kommentar.

## Från en molnsession

`gh issue` fungerar inte i molnsessioner (GraphQL är avstängt). Använd REST:

- Läs: `gh api repos/pissmyran/bastion_apple/issues/<n>` och `…/issues/<n>/comments`
- Lista öppna: `gh api 'repos/pissmyran/bastion_apple/issues?state=open'`
- Skapa: `gh api repos/pissmyran/bastion_apple/issues -f title='…' -f body='…'`
- Kommentera: `gh api repos/pissmyran/bastion_apple/issues/<n>/comments -f body='…'`
- Stäng: `gh api -X PATCH repos/pissmyran/bastion_apple/issues/<n> -f state=closed`
