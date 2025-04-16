# Projet GCP avec Terraform

Ce projet configure une infrastructure Google Cloud Platform (GCP) à l'aide de Terraform. Il inclut la création de réseaux, de sous-réseaux, de pare-feu, de machines virtuelles (VM), d'un Load Balancer, et d'une passerelle VPN.

## Structure du projet

- **main.tf** : Fichier principal contenant la configuration Terraform pour l'infrastructure GCP.
- **kubernetes-nginx-project/** : Dossier contenant des fichiers liés à Kubernetes.
  - **manifests/** : Contient les fichiers YAML pour les ressources Kubernetes.
    - **deployment.yaml** : Déploiement Kubernetes.
    - **namespace.yaml** : Namespace Kubernetes.
    - **service.yaml** : Service Kubernetes.

## Prérequis

- Un compte Google Cloud Platform avec un projet configuré.
- Terraform installé sur votre machine.
- Les permissions nécessaires pour créer des ressources sur GCP.

## Configuration

1. Clonez ce dépôt sur votre machine locale.
2. Assurez-vous que Terraform est installé en exécutant :
   ```bash
   terraform --version
   ```
3. Modifiez les variables dans le fichier `main.tf` si nécessaire :
   - `project_id` : ID de votre projet GCP.
   - `region` : Région GCP.
   - `zone` : Zone GCP.

## Déploiement

1. Initialisez Terraform :
   ```bash
   terraform init
   ```
2. Vérifiez le plan de déploiement :
   ```bash
   terraform plan
   ```
3. Appliquez le plan pour créer les ressources :
   ```bash
   terraform apply
   ```

## Ressources créées

- **VPC** : Réseau sécurisé avec des sous-réseaux publics et privés.
- **VM** : Machines virtuelles dans les sous-réseaux public et privé.
- **Load Balancer** : Pour exposer la VM privée via une IP publique.
- **VPN** : Passerelle VPN pour connecter des réseaux distants.
- **Pare-feu** : Règles pour autoriser le trafic SSH, HTTP, et ICMP.

## Outputs

Après le déploiement, Terraform affichera les informations suivantes :

- Nom du VPC
- Noms des sous-réseaux public et privé
- IP interne et externe de la VM publique
- IP interne de la VM privée
- Nom de la passerelle VPN
- Nom du tunnel VPN

## Nettoyage

Pour supprimer toutes les ressources créées, exécutez :
```bash
terraform destroy
```

## Notes

- Assurez-vous de sécuriser les secrets et les informations sensibles (comme `shared_secret` pour le VPN).
- Vérifiez les coûts associés aux ressources GCP créées.