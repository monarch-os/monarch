import argparse

def unique(target_file, output_file):

    # Dictionnaire pour stocker les valeurs uniques
    entrees_uniques = {}

    # Lire le fichier source
    with open(target_file, "r") as fichier:
        lignes = fichier.readlines()

    # Filtrer les lignes en supprimant les doublons
    with open(output_file, "w") as fichier_sans_doublons:
        for ligne in lignes:
            # Extraire la chaîne avant '::'
            partie_avant_double_colon = ligne.split("::")[0]

            # Si cette chaîne n'a pas encore été rencontrée, on l'ajoute
            if partie_avant_double_colon not in entrees_uniques:
                entrees_uniques[partie_avant_double_colon] = ligne
                # Écrire la ligne dans le nouveau fichier
                fichier_sans_doublons.write(ligne)

    print(f"Opération terminée. Les doublons ont été supprimés. Le fichier nettoyé est '{output_file}'.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extrait un unique hash pour chaque utilisteur relayé du fichier généré par ntlmrelayx")
    parser.add_argument("-tf", "--target_file", help="Target file containing hashes", required=True)
    parser.add_argument("-o", "--output_file", help="Output file name", required=True)
    
    args = parser.parse_args()

    unique(args.target_file, args.output_file)