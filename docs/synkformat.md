# Synkformat

Bastion för Apple är **källan** till synkformatet. Swift-modellerna i `Sources/SSHCore/` (`Host`, `HostStore`, `Snippet`, `SyncEngine` och `SyncCrypto`) definierar formatet, och fixturerna i `Tests/fixtures/` är kontraktet som de andra plattformarna testar mot.

## När formatet ändras

1. Ändra Swift-modellen och fixturen i samma PR, och skriv i PR:en att formatet ändrats.
2. Skapa ett issue i varje berört plattformsrepo ([Linux](https://github.com/pissmyran/bastion_linux), [Windows](https://github.com/pissmyran/bastion_windows)) med länk till PR:en, så att deras kopior av fixturerna och deras läsare uppdateras.
3. Ändra aldrig en fixtur bara för att få ett test grönt. Faller testet har formatet ändrats, och då är frågan vad som händer med filer som användarna redan har sparat.
